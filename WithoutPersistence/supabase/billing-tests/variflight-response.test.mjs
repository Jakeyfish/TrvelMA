import test from 'node:test';
import assert from 'node:assert/strict';
import {successfulFlightResponse} from '../functions/_shared/variflight-response.ts';

test('only populated successful provider replies are eligible for a refresh charge', () => {
  const result = text => JSON.stringify({result:{content:[{type:'text',text}]}});
  assert.equal(successfulFlightResponse(result('[{"FlightNo":"JX2"}]')),true);
  assert.equal(successfulFlightResponse('data: '+result('[{"FlightNo":"JX2"}]')),true);
  assert.equal(successfulFlightResponse(result('Error executing tool: failed')),false);
  assert.equal(successfulFlightResponse(result('[]')),false);
  assert.equal(successfulFlightResponse(JSON.stringify({result:{isError:true}})),false);
  assert.equal(successfulFlightResponse('not JSON'),false);
});
