# Creates the app-scoped beta tester for Duo Flicky (tester records are
# per-app in App Store Connect) and assigns the account holder to the
# internal test group in the same call.
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
TOKEN = "#{input}.#{b64(parts.join)}"

def call(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  if body
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
  end
  res = http.request(req)
  [res.code.to_i, res.body]
end

GROUP = '83734e04-fb54-4f19-894b-3a8e96f93415'
APP = '6834985456'

# Skip if a Duo Flicky-scoped tester already exists.
code, body = call(:get, "/v1/apps/#{APP}/betaTesters?fields[betaTesters]=email,state,inviteType")
existing = JSON.parse(body)['data'] || []
puts "APP_TESTERS(#{existing.size})"
existing.each { |t| puts "  #{t['id']} #{t['attributes']['email']} state=#{t['attributes']['state']}" }

if existing.empty?
  code, body = call(:post, '/v1/betaTesters', {
    data: {
      type: 'betaTesters',
      attributes: {
        email: 'firecracker.rebirth@gmail.com',
        firstName: '将人',
        lastName: '越川'
      },
      relationships: {
        betaGroups: { data: [{ type: 'betaGroups', id: GROUP }] }
      }
    }
  })
  puts "CREATE_TESTER -> #{code}"
  if code == 201
    t = JSON.parse(body)['data']
    puts "NEW TESTER #{t['id']} state=#{t['attributes']['state']} invite=#{t['attributes']['inviteType']}"
  else
    puts body
  end
end

code, body = call(:get, "/v1/betaGroups/#{GROUP}/betaTesters?fields[betaTesters]=email,state")
group_testers = JSON.parse(body)['data'] || []
puts "GROUP_TESTERS_NOW(#{group_testers.size})"
group_testers.each { |t| puts "  #{t['id']} #{t['attributes']['email']} state=#{t['attributes']['state']}" }
