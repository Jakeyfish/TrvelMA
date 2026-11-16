import test from 'node:test';
import assert from 'node:assert/strict';
import {statementPDF} from '../statement-pdf.mjs';
const page=()=>({bytes:new Uint8Array([255,216,255,217]),width:842,height:595,pixelWidth:1684,pixelHeight:1190});
test('PDF stores every page and exact binary stream lengths with valid cross-reference offsets',()=>{
 const pdf=statementPDF([page(),page()]);const text=new TextDecoder().decode(pdf);
 assert.match(text,/^%PDF-1.4/);assert.match(text,/\/Count 2/);assert.match(text,/\/Kids \[3 0 R 6 0 R\]/);
 const xref=Number(text.match(/startxref\n(\d+)/)[1]);assert.equal(new TextDecoder().decode(pdf.slice(xref,xref+4)),'xref');
 const entries=text.slice(text.indexOf('xref\n')).split('\n').slice(3,11);
 entries.forEach((line,i)=>{const offset=Number(line.slice(0,10));assert.equal(new TextDecoder().decode(pdf.slice(offset,offset+`${i+1} 0 obj`.length)),`${i+1} 0 obj`);});
 assert.equal((text.match(/\/Filter \/DCTDecode/g)||[]).length,2);
 assert.equal((text.match(/\/Length 4 >>/g)||[]).length,2);
});
test('PDF rejects empty or invalid rendered pages instead of sharing a corrupt file',()=>{
 assert.throws(()=>statementPDF([]));assert.throws(()=>statementPDF([{...page(),width:NaN}]));
 assert.throws(()=>statementPDF([{...page(),bytes:new Uint8Array([1,2,3,4])}]));
});
