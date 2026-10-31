import {test} from 'node:test';
import assert from 'node:assert/strict';
import {inspectCloudConfig} from '../scripts/check-cloud-db-config.mjs';
const config=`KINNECT_DATABASE_PROVIDER=postgres
KINNECT_DATABASE_URL=postgresql://app:secret@db.example.com:5432/kinnect?sslmode=verify-full
KINNECT_DATABASE_CA_FILE=
KINNECT_DATABASE_POOL_MAX=10
KINNECT_DATABASE_CONNECT_TIMEOUT_MS=10000
KINNECT_MEDIA_PROVIDER=local`;
test('valid configuration never claims production readiness or reveals credentials',()=>{
 const result=inspectCloudConfig(config);assert.equal(result.valid,true);assert.equal(result.productionReady,false);assert.ok(!JSON.stringify(result).includes('secret'));
});
test('reject placeholders, weak TLS, invalid pool and missing CA',()=>{
 for(const value of [config.replace('secret','CHANGE_ME'),config.replace('verify-full','require'),config.replace('POOL_MAX=10','POOL_MAX=0'),config.replace('CA_FILE=','CA_FILE=missing')])assert.equal(inspectCloudConfig(value,{fileExists:()=>false}).valid,false);
});
test('duplicate keys fail without echoing connection data',()=>{
 assert.throws(()=>inspectCloudConfig(config+'\nKINNECT_DATABASE_URL=secret'),/Duplicate configuration key/);
});
