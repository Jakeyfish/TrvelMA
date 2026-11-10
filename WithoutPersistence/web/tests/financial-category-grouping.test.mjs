import test from 'node:test';
import assert from 'node:assert/strict';
import {financialCategoryGroups} from '../parity.mjs';
test('same fee has one category with preserved income and expense subtotals',()=>{
 const rows=financialCategoryGroups([{title:'停车费',amount:11,isAddition:false},{title:'停车费',amount:3,isAddition:true},{title:'停车费',amount:2,isAddition:false}]);
 assert.equal(rows.length,1);assert.equal(rows[0].incomeAmount,3);assert.equal(rows[0].expenseAmount,13);assert.equal(rows[0].amount,16);
});
test('whitespace unicode and empty names normalize before grouping',()=>{
 const rows=financialCategoryGroups([{title:' Parking  fee\n',amount:2},{title:'Parking\tfee',amount:3},{title:'Café',amount:4},{title:'Cafe\u0301',amount:1},{title:' ',amount:2},{title:'其他',amount:3}]);
 assert.equal(rows.length,3);assert.deepEqual(rows.map(r=>r.amount),[5,5,5]);
});
test('nonfinite and zero entries do not produce slices',()=>{
 const rows=financialCategoryGroups([{title:'a',amount:NaN},{title:'b',amount:0},{title:'c',amount:Infinity},{title:'d',amount:-11}]);
 assert.equal(rows.length,1);assert.equal(rows[0].expenseAmount,11);
});
