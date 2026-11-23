'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
const {validatePost,validateReply,validateId,HttpError}=require('../src/lib/validate');
const valid={kind:'need',title:'Cieknący kran w kuchni',description:'Bateria w kuchni stale przecieka, potrzebuję naprawy.',category:'Hydraulika',city:'Szczecin',budget:'Do 150 zł',urgency:'Pilne'};
test('poprawne ogloszenie',()=>assert.equal(validatePost(valid).city,'Szczecin'));
test('blokuje obca kategorie',()=>assert.throws(()=>validatePost({...valid,category:'Admin'}),HttpError));
test('blokuje zbyt krotki opis',()=>assert.throws(()=>validatePost({...valid,description:'Kran'}),HttpError));
test('sprawdza odpowiedz',()=>{assert.equal(validateReply({message:'Mogę pomóc jutro rano.'}),'Mogę pomóc jutro rano.');assert.throws(()=>validateReply({message:'Ok'}),HttpError)});
test('sprawdza UUID',()=>{assert.equal(validateId('550e8400-e29b-41d4-a716-446655440000'),'550e8400-e29b-41d4-a716-446655440000');assert.throws(()=>validateId('..\\etc'),HttpError)});
