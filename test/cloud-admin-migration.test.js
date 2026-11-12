import {test} from 'node:test';import assert from 'node:assert/strict';import {DatabaseSync} from 'node:sqlite';import {openSocial} from '../lib/social.js';import {createAdminConsole} from '../lib/admin-console.js';import {consoleSnapshot} from '../cloud-admin/export.js';import {importRows} from '../cloud-admin/schema.js';
test('cloud migration preserves video relationships, excludes native credentials/sessions and never overwrites cloud-owned staff',t=>{
 const source=openSocial(':memory:'),route=createAdminConsole(source),target=new DatabaseSync(':memory:');t.after(()=>{route.close();source.close();target.close();});
 source.db.prepare("INSERT INTO users(id,username,name,password,salt,created,role,birth_date,avatar) VALUES('user','fixture','Fixture','private-native-hash','private-native-salt',1,'user','',?)").run(Buffer.alloc(1500000,1));
 source.db.prepare("INSERT INTO shorts(id,user_id,caption,data,duration,hidden,created) VALUES('video','user','Fixture',?,10,0,1)").run(Buffer.alloc(2500000,2));
 source.db.prepare("INSERT INTO short_likes VALUES('video','user')").run();source.db.prepare("INSERT INTO sessions VALUES('native-session','user',9999999999999)").run();
 source.db.prepare("INSERT INTO console_staff(id,username,name,password,salt,created) VALUES('staff','staff','Fixture','staff-hash','staff-salt',1)").run();
 const snapshot=consoleSnapshot(source.db,{owned:true});assert(!snapshot.tables.some(t=>t.name==='sessions'));
 target.exec('PRAGMA foreign_keys=ON');for(const schema of snapshot.schemas)target.exec(schema.sql);
 for(let n=0;n<2;n++)for(const table of snapshot.tables)importRows(target,table.name,table.columns,table.rows);
 assert.equal(target.prepare('SELECT count(*) n FROM shorts').get().n,1);assert.equal(target.prepare('SELECT count(*) n FROM short_likes').get().n,1);assert.equal(target.prepare('SELECT length(data) n FROM shorts').get().n,0);assert.equal(target.prepare('PRAGMA foreign_key_check').all().length,0);
 const user=target.prepare('SELECT password,salt,avatar FROM users').get();assert.equal(user.password,'');assert.equal(user.salt,'');assert.equal(user.avatar,null);
 assert.equal(target.prepare('SELECT count(*) n FROM sessions').get().n,0);assert.equal(target.prepare('SELECT password FROM console_staff').get().password,'staff-hash');
 target.prepare("UPDATE console_staff SET password='new-cloud-hash' WHERE id='staff'").run();const staff=snapshot.tables.find(t=>t.name==='console_staff');importRows(target,staff.name,staff.columns,staff.rows);assert.equal(target.prepare('SELECT password FROM console_staff').get().password,'new-cloud-hash');
});
