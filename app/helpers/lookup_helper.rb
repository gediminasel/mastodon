# frozen_string_literal: true

#noinspection RubyClassVariableUsageInspection
class VerifierKeys
  @@verifier_keys = nil

  def self.verifier_keys
    return @@verifier_keys unless @@verifier_keys.nil?
    begin
      @@verifier_keys = JSON.parse File.read(ENV['VERIFIERS_FILE'])
    rescue => e
      p e
      @@verifier_keys = {}
    end
    @@verifier_keys.each do |uri, key|
      next unless key.nil?
      begin
        actor = Class.new.extend(JsonLdHelper).fetch_resource_without_id_validation(uri)
        @@verifier_keys[uri] = actor['publicKey']['publicKeyPem']
      rescue => e
        p e
      end
    end
    File.open(ENV['VERIFIERS_FILE'], 'w') do |f|
      f.write(JSON.pretty_generate(@@verifier_keys))
    end
    @@verifier_keys.each do |uri, key|
      @@verifier_keys[uri] = OpenSSL::PKey::RSA.new key unless key.nil?
    end
    @@verifier_keys
  end
end

module LookupHelper

  def extract_lookup_data(data)
    return nil if data.nil?

    signatures = data['key_signatures']
    return if signatures.nil? || !signatures.kind_of?(Array)

    json = data['json']
    json = JSON.parse json
    return if json.nil?

    verified = signatures_valid(json, signatures)
    return nil if verified.include? false
    return json if verified.count(true) >= 1
    nil
  end

  def signatures_valid(json, signatures)
    verifier_keys = VerifierKeys.verifier_keys

    signatures.map do |v|
      signed_by = v['signed_by']
      signature = Base64.decode64(v['signature'])
      signature_time = v['signature_time']
      signed_string = create_signed_string(json, signature_time)
      next nil if verifier_keys[signed_by].nil?
      correct_signature?(verifier_keys[signed_by], signature, signed_string)
    end
  end

  def correct_signature?(public_key, signature, signed_string)
    public_key.verify(OpenSSL::Digest.new('SHA256'), signature, signed_string)
  rescue OpenSSL::PKey::RSAError
    false
  end

  def create_signed_string(json, sign_time)
    actor_key = json['publicKey'] || {}
    to_sign = {
      "actor_id": json['id'],
      "actor_uri": json['uri'],
      "key": Hash[actor_key.sort],
      "signature_time": sign_time,
    }
    JSON.generate(Hash[to_sign.sort])
  end
end
