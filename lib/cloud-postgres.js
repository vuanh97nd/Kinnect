import {readFileSync} from 'node:fs';
export function postgresOptions(config){
 const url=new URL(config.KINNECT_DATABASE_URL);
 if(!['postgres:','postgresql:'].includes(url.protocol)||url.searchParams.get('sslmode')!=='verify-full')throw Error('Verified PostgreSQL TLS is required.');
 if(!config.KINNECT_DATABASE_CA_FILE)throw Error('Provider CA file is required.');
 url.searchParams.delete('sslmode');
 return {connectionString:url.toString(),ssl:{ca:readFileSync(config.KINNECT_DATABASE_CA_FILE,'utf8'),rejectUnauthorized:true},connectionTimeoutMillis:10000,query_timeout:30000};
}
