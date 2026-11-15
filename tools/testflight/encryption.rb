require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'

KEY_ID = 'NBH484P5G6'
ISS = '94f4f5a7-ccba-45ef-b191-497842793d88'
key = OpenSSL::PKey.read(File.read(File.expand_path('~/.appstoreconnect/private_keys/AuthKey_NBH484P5G6.p8')))

def b64(bin)
  Base64.urlsafe_encode64(bin, padding: false)
end

now = Time.now.to_i
header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' }
payload = { iss: ISS, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }
input = "#{b64(header.to_json)}.#{b64(payload.to_json)}"
asn1 = key.sign(OpenSSL::Digest::SHA256.new, input)
seq = OpenSSL::ASN1.decode(asn1)
parts = seq.value.map do |int|
  bin = int.value.to_s(2)
  bin = ("\x00" * (32 - bin.bytesize)) + bin if bin.bytesize < 32
  bin.byteslice(bin.bytesize - 32, 32)
end
token = "#{input}.#{b64(parts.join)}"

build_id = ARGV[0]
uri = URI("https://api.appstoreconnect.apple.com/v1/builds/#{build_id}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
req = Net::HTTP::Patch.new(uri)
req['Authorization'] = "Bearer #{token}"
req['Content-Type'] = 'application/json'
req.body = {
  data: {
    type: 'builds', id: build_id,
    attributes: { usesNonExemptEncryption: false }
  }
}.to_json
res = http.request(req)
puts "PATCH builds/#{build_id} -> #{res.code}"
puts res.body
