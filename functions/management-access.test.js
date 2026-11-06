'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {isCentralAdmin,canManageMunicipality}=require('./management-access');
const {aggregateManagementReports}=require('./management-dashboard');

test('un administrador municipal no adquiere alcance global por su rol',()=>{
  const profile={role:'admin',municipalityId:'060441'};
  assert.equal(isCentralAdmin(profile),false);
  assert.equal(canManageMunicipality(profile,'060441'),true);
  for(const scope of ['060707','georef_060441','',null])assert.equal(canManageMunicipality(profile,scope),false);
});
test('el acceso central requiere organización, rol y cuenta habilitada',()=>{
  const central={role:'admin',organizationId:'diagonales'};
  assert.equal(isCentralAdmin(central),true);
  assert.equal(canManageMunicipality(central,'060707'),true);
  for(const profile of [{...central,disabled:true},{...central,role:'citizen'},{...central,organizationId:'otra'},null]){
    assert.equal(isCentralAdmin(profile),false);
    assert.equal(canManageMunicipality(profile,'060707'),false);
  }
});
test('un perfil operativo sin municipio no puede usar un ámbito vacío',()=>{
  for(const role of ['admin','coordinator','moderator','field_worker','citizen']){
    assert.equal(canManageMunicipality({role},undefined),false);
    assert.equal(canManageMunicipality({role,municipalityId:''},''),false);
  }
});
test('indicadores excluyen retirados, conservan estados desconocidos y no divulgan textos ni contactos',()=>{
  const now=new Date('2026-10-31T12:00:00Z');
  const common={municipalityId:'060441',hidden:false,category:'infrastructure',description:'PRIVADO',email:'privado@example.test'};
  const result=aggregateManagementReports([
    {...common,status:'pending',createdAt:new Date('2020-01-01'),priority:5},
    {...common,status:'nuevo_estado',createdAt:now},
    {...common,status:'resolved',createdAt:new Date('2026-10-29T12:00:00Z'),resolvedAt:new Date('2026-10-30T12:00:00Z')},
    {...common,status:'closed',createdAt:new Date('2026-10-25T12:00:00Z'),resolvedAt:new Date('2026-10-30T12:00:00Z')},
    {...common,status:'pending',hidden:true},
  ],now);
  assert.equal(result.totals.total,4);
  assert.equal(result.totals.open,2);
  assert.equal(result.totals.unknownStatus,1);
  assert.equal(result.totals.over72h,1);
  assert.equal(result.totals.highPriorityOpen,1);
  assert.equal(result.totals.resolvedWeek,2);
  assert.equal(result.totals.medianResolutionHours,72);
  assert.doesNotMatch(JSON.stringify(result),/PRIVADO|privado@example/);
});
test('un municipio sin cierres no muestra una falsa resolución de cero horas',()=>{
  const result=aggregateManagementReports([]);
  assert.equal(result.totals.total,0);
  assert.equal(result.totals.medianResolutionHours,null);
  assert.equal(result.totals.p90ResolutionHours,null);
});
