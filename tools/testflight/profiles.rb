require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'

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
  puts "== #{method.upcase} #{path} -> #{res.code}"
  res
end

# 1. Find a distribution certificate.
res = call(:get, '/v1/certificates?limit=200&fields[certificates]=certificateType,name,expirationDate,displayName')
certs = JSON.parse(res.body)['data'] || []
dist = certs.select { |c| %w[DISTRIBUTION IOS_DISTRIBUTION].include?(c['attributes']['certificateType']) }
dist.each { |c| puts "DIST_CERT #{c['id']} #{c['attributes']['certificateType']} #{c['attributes']['displayName']} exp=#{c['attributes']['expirationDate']}" }
cert_id = dist.first && dist.first['id']
abort 'NO_DIST_CERT' unless cert_id

# 2. Bundle ID record ids.
res = call(:get, '/v1/bundleIds?filter[identifier]=jp.duoflicky.app,jp.duoflicky.app.keyboard&fields[bundleIds]=identifier')
bids = {}
(JSON.parse(res.body)['data'] || []).each { |b| bids[b['attributes']['identifier']] = b['id'] }
puts "BUNDLE_IDS #{bids.inspect}"

# 3. Create App Store profiles and save the .mobileprovision files.
outdir = File.expand_path('~/muse-build/duo-tf/profiles')
FileUtils.mkdir_p(outdir)
{
  'jp.duoflicky.app' => 'Duo Flicky App Store',
  'jp.duoflicky.app.keyboard' => 'Duo Flicky Keyboard App Store'
}.each do |identifier, name|
  res = call(:post, '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: { name: name, profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bids[identifier] } },
        certificates: { data: [{ type: 'certificates', id: cert_id }] }
      }
    }
  })
  if res.code.to_i == 201
    parsed = JSON.parse(res.body)['data']
    content = parsed['attributes']['profileContent']
    path = File.join(outdir, "#{name.gsub(' ', '_')}.mobileprovision")
    File.binwrite(path, Base64.decode64(content))
    puts "PROFILE_SAVED #{identifier} uuid=#{parsed['attributes']['uuid']} -> #{path}"
  else
    puts res.body
  end
end
