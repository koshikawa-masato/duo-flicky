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
  req = case method
        when :post then Net::HTTP::Post.new(uri)
        else Net::HTTP::Get.new(uri)
        end
  req['Authorization'] = "Bearer #{TOKEN}"
  if body
    req['Content-Type'] = 'application/json'
    req.body = body.to_json
  end
  res = http.request(req)
  [res.code.to_i, res.body]
end

code, body = call(:get, '/v1/apps?filter[bundleId]=jp.duoflicky.app&fields[apps]=name,bundleId,sku')
apps = JSON.parse(body)['data'] || []
abort 'APP_NOT_FOUND' if apps.empty?
app = apps[0]
app_id = app['id']
puts "APP #{app_id} #{app['attributes']['name']} sku=#{app['attributes']['sku']}"

mode = ARGV[0] || 'status'
if mode == 'appid'
  exit 0
end

code, body = call(:get, "/v1/builds?filter[app]=#{app_id}&sort=-uploadedDate&limit=5&fields[builds]=version,uploadedDate,processingState,expired")
builds = JSON.parse(body)['data'] || []
if builds.empty?
  puts 'NO_BUILDS_YET'
  exit 0
end
build = builds[0]
puts "BUILD #{build['id']} version=#{build['attributes']['version']} state=#{build['attributes']['processingState']} expired=#{build['attributes']['expired']} uploaded=#{build['attributes']['uploadedDate']}"

if mode == 'groupadd' && build['attributes']['processingState'] == 'VALID'
  code, body = call(:get, "/v1/apps/#{app_id}/betaGroups?fields[betaGroups]=name,isInternalGroup")
  groups = JSON.parse(body)['data'] || []
  internal = groups.find { |g| g['attributes']['isInternalGroup'] }
  unless internal
    code, body = call(:post, '/v1/betaGroups', {
      data: {
        type: 'betaGroups',
        attributes: { name: '内部テスト', isInternalGroup: true },
        relationships: { app: { data: { type: 'apps', id: app_id } } }
      }
    })
    puts "CREATE_GROUP -> #{code}"
    puts body unless code == 201
    internal = JSON.parse(body)['data'] if code == 201
  end
  puts "GROUP #{internal['id']} #{internal['attributes']['name']}"
  code, body = call(:post, "/v1/betaGroups/#{internal['id']}/relationships/builds", {
    data: [{ type: 'builds', id: build['id'] }]
  })
  puts "ADD_BUILD -> #{code}"
  puts body unless [200, 201, 204].include?(code)
end
