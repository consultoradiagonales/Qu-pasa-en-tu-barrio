const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
 fs.mkdirSync('ERRORES/CAPTURAS/QA', { recursive: true });
 const browser = await chromium.launch({executablePath:'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',headless:true});
 const context = await browser.newContext({permissions:['geolocation'],geolocation:{latitude:-35.6384,longitude:-59.7779}});
 const page = await context.newPage();
 page.on('pageerror',e=>console.log('PAGEERROR',e.message));
 page.on('console',m=>{if(m.type()==='error')console.log('ERROR',m.text())});
 await page.goto('https://project-5fc9024a-e961-42b7-9ee.web.app');
 await page.evaluate(async()=>{
  const {initializeApp}=await import('https://www.gstatic.com/firebasejs/11.0.0/firebase-app.js');
  const {getAuth,createUserWithEmailAndPassword}=await import('https://www.gstatic.com/firebasejs/11.0.0/firebase-auth.js');
  const app=initializeApp({apiKey:'AIzaSyAq8vtaTmwWkYaJGSdXj6wtbhGwWLZm00Y',authDomain:'project-5fc9024a-e961-42b7-9ee.firebaseapp.com',projectId:'project-5fc9024a-e961-42b7-9ee'});
  const cred=await createUserWithEmailAndPassword(getAuth(app),'mapqa.'+Date.now()+'@example.com','Qa!'+crypto.randomUUID());
  const token=await cred.user.getIdToken();
  const fields={role:{stringValue:'citizen'},disabled:{booleanValue:false},municipalityId:{stringValue:'060707'},reportsCount:{integerValue:'0'}};
  await fetch('https://firestore.googleapis.com/v1/projects/project-5fc9024a-e961-42b7-9ee/databases/(default)/documents/users/'+cred.user.uid,{method:'PATCH',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({fields})});
 });
 await page.goto('https://project-5fc9024a-e961-42b7-9ee.web.app/#/map');
 await page.waitForTimeout(15000);
 console.log(await page.evaluate(()=>({maps:typeof google?.maps,tiles:document.querySelectorAll('.gm-style img').length,text:document.body.innerText.slice(0,500)})));
 await page.screenshot({path:'ERRORES/CAPTURAS/QA/map-qa.png'});
 await browser.close();
})();
