import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {localized, translations} from '../localization.mjs';
import {buildAgencyStatement} from '../parity.mjs';
const languages=['zh-Hans','zh-Hant','en','es','ja','ko'];
test('new labels cover every supported language and preserve format placeholders',()=>{
 for(const [key,values] of Object.entries(translations)) {
  if(!values['zh-Hans']) continue;
  for(const language of languages){
   assert.ok(values[language],`${key}: ${language}`);
   assert.deepEqual(values[language].match(/%@|%ld/g)||[],values['zh-Hans'].match(/%@|%ld/g)||[],`${key}: ${language}`);
  }
 }
});
test('localized statements retain customer data, custom fees and unsigned fee totals',()=>{
 const trip={appointment_date:'2026-11-02',travel_agency_order_number:'C-123',service_type:'接机',customer_name:'王先生',location_start:'LAX',location_end:'Hotel',price:100,expenses:[{title:'停车费',amount:-8}],currency_code:'USD'};
 for(const language of languages){
  const report=buildAgencyStatement([trip],key=>localized(key,language),language);
  assert.equal(report.headers[1],localized('订单号',language));
  assert.equal(report.headers[8],'停车费');
  assert.equal(report.rows[0][3],'王先生');
  assert.equal(report.rows[0][1],'C-123');
  assert.equal(report.totals.USD,108);
 }
 assert.equal(localized('对账单（%ld 条）','en',2),'Statement (2)');
});
test('Web shared translations match the App catalog',()=>{
 const catalog=JSON.parse(fs.readFileSync(new URL('../../Wishlist/Localizable.xcstrings',import.meta.url),'utf8')).strings;
 for(const [key,values] of Object.entries(translations))for(const language of languages){
  const unit=catalog[key]?.localizations?.[language]?.stringUnit;
  assert.equal(values[language],unit?.value ?? (language==='zh-Hans'?key:undefined),`${language}: ${key}`);
 }
});
test('entry point and imported UI modules share the release version to prevent stale translations',()=>{
 const entry=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
 const app=fs.readFileSync(new URL('../app.js',import.meta.url),'utf8');
 const version=entry.match(/app\.js\?v=([^"\s]+)/)?.[1];
 assert.ok(version);
 assert.ok(entry.includes(`styles.css?v=${version}`));
 assert.ok(app.includes(`localization.mjs?v=${version}`));
 assert.ok(app.includes(`parity.mjs?v=${version}`));
});
