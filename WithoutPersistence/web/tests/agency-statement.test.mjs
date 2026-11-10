import test from 'node:test';
import assert from 'node:assert/strict';
import { agencyStatementTrips, buildAgencyStatement } from '../parity.mjs';
const trip = (id, extra={}) => ({id,order_source:'旅行社订单',travel_agency_code:'A',appointment_date:'2026-11-01',appointment_time:'10:00',price:100,tip:5,currency_code:'USD',expenses:[],...extra});
test('statement excludes paid, cancelled, ordinary and other agency trips; stable order',()=>{
 const rows=[trip('2'),trip('1'),trip('p',{is_paid:true}),trip('c',{is_cancelled:true}),trip('n',{order_source:'普通客户'}),trip('b',{travel_agency_code:'B'})];
 assert.deepEqual(agencyStatementTrips(rows,'code:A').map(t=>t.id),['1','2']);
 assert.deepEqual(agencyStatementTrips(rows,''),[]);
});
test('dynamic columns aggregate repeated fees and sum absolute fees into one title',()=>{
 const rows=[trip('1',{expenses:[{title:'停车费',amount:11,is_addition:true},{title:'停车费',amount:2,is_addition:true},{title:'打印费',amount:3,is_addition:true},{title:'停车费',amount:4,is_addition:false}]})];
 const before=JSON.stringify(rows), report=buildAgencyStatement(rows);
 assert.equal(report.rows[0][report.headers.indexOf('停车费')],'$17.00');
 assert.equal(report.headers.filter(h => h === '停车费').length,1);
 assert.ok(!report.headers.includes('时间') && !report.headers.includes('小费') && !report.headers.includes('币种'));
 assert.equal(report.totals.USD,120); assert.equal(JSON.stringify(rows),before);
});
test('totals never mix currencies and empty report is valid',()=>{
 assert.deepEqual(buildAgencyStatement([trip('u'),trip('e',{currency_code:'EUR',price:10})]).totals,{USD:100,EUR:10});
 assert.deepEqual(buildAgencyStatement([]).rows,[]);
});

test('each row total equals fare plus horizontal absolute fee columns, excluding tips',()=>{
 const report=buildAgencyStatement([trip('x',{tip:999,expenses:[{title:'停车费',amount:-11,is_addition:false},{title:'打印费',amount:3,is_addition:true}]})]);
 const row=report.rows[0];
 assert.equal(row[report.headers.indexOf('停车费')],'$11.00');
 assert.equal(row.at(-1),'$114.00');
 assert.equal(report.totals.USD,114);
});
