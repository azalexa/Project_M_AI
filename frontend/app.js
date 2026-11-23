'use strict';

const cfg = window.MECHMASTER_CONFIG || {};
const $ = id => document.getElementById(id);
const DEMO = !cfg.apiBaseUrl;
const DEMO_POSTS_KEY = 'mechmaster.marketplace.demo.posts.v1';
const DEMO_REPLIES_KEY = 'mechmaster.marketplace.demo.replies.v1';
const DEMO_MESSAGES_KEY = 'mechmaster.marketplace.demo.messages.v1';
const CATS = ['Motoryzacja', 'Hydraulika', 'Elektryka', 'AGD', 'Dom i ogród', 'Komputery', 'Inne'];
const CAT_ICON = {Motoryzacja:'🚗',Hydraulika:'🚰',Elektryka:'⚡',AGD:'🧺','Dom i ogród':'🏠',Komputery:'💻',Inne:'🛠️'};
const DAY = 86400000;
const SAMPLE = [
  {id:'sample-1',kind:'need',title:'Samochód nie odpala po nocy',description:'Ford Focus kręci rozrusznikiem, ale silnik nie podejmuje pracy. Problem zaczął się wczoraj. Szukam osoby, która pomoże ustalić przyczynę.',category:'Motoryzacja',city:'Szczecin',budget:'Do ustalenia',urgency:'Pilne',authorName:'Michał',authorId:'example-1',createdAt:new Date(Date.now()-1.6*3600000).toISOString(),replyCount:3,status:'open',sample:true},
  {id:'sample-2',kind:'need',title:'Cieknący kran w kuchni',description:'Z baterii kuchennej stale kapie woda, nawet po zakręceniu. Potrzebuję pomocy z wymianą uszczelki lub baterii.',category:'Hydraulika',city:'Warszawa',budget:'Do 200 zł',urgency:'W tym tygodniu',authorName:'Ania',authorId:'example-2',createdAt:new Date(Date.now()-4*3600000).toISOString(),replyCount:2,status:'open',sample:true},
  {id:'sample-3',kind:'offer',title:'Pomogę z naprawą komputerów i laptopów',description:'Diagnozuję usterki, czyszczę laptopy, instaluję systemy i pomagam z konfiguracją sieci domowych. Oferuję pomoc na miejscu w Gdańsku.',category:'Komputery',city:'Gdańsk',budget:'Od 80 zł',urgency:'Elastycznie',authorName:'Krzysztof',authorId:'example-3',createdAt:new Date(Date.now()-7*3600000).toISOString(),replyCount:0,status:'open',sample:true},
  {id:'sample-4',kind:'need',title:'Pralka zatrzymuje się w połowie programu',description:'Pralka pobiera wodę, jednak po kilkunastu minutach kończy pracę i wyświetla błąd. Szukam wskazówek albo wizyty serwisowej.',category:'AGD',city:'Kraków',budget:'Do ustalenia',urgency:'W tym tygodniu',authorName:'Kasia',authorId:'example-4',createdAt:new Date(Date.now()-1.2*DAY).toISOString(),replyCount:1,status:'open',sample:true},
  {id:'sample-5',kind:'offer',title:'Hydraulik — drobne naprawy i montaż',description:'Pomogę z cieknącymi kranami, syfonami, uszczelkami i wymianą armatury. Dogodny termin po ustaleniu szczegółów.',category:'Hydraulika',city:'Poznań',budget:'Od 100 zł',urgency:'Elastycznie',authorName:'Tomasz',authorId:'example-5',createdAt:new Date(Date.now()-1.8*DAY).toISOString(),replyCount:0,status:'open',sample:true},
  {id:'sample-6',kind:'need',title:'Nie działa oświetlenie w przedpokoju',description:'Żarówki są sprawne, ale światło przestało działać. Szukam osoby z uprawnieniami do sprawdzenia instalacji.',category:'Elektryka',city:'Wrocław',budget:'Do ustalenia',urgency:'W tym tygodniu',authorName:'Paweł',authorId:'example-6',createdAt:new Date(Date.now()-2.3*DAY).toISOString(),replyCount:1,status:'open',sample:true},
  {id:'sample-7',kind:'offer',title:'Montaż półek, naprawy i prace domowe',description:'Pomagam przy skręcaniu mebli, montażu półek i drobnych naprawach domowych. Dostępność po wcześniejszym ustaleniu.',category:'Dom i ogród',city:'Łódź',budget:'Do ustalenia',urgency:'Elastycznie',authorName:'Bartek',authorId:'example-7',createdAt:new Date(Date.now()-3*DAY).toISOString(),replyCount:0,status:'open',sample:true},
  {id:'sample-8',kind:'offer',title:'Diagnostyka samochodów, kody OBD',description:'Pomogę odczytać i zinterpretować kody usterek, sprawdzić podstawowe parametry pracy silnika i ustalić kolejne kroki.',category:'Motoryzacja',city:'Szczecin',budget:'Od 70 zł',urgency:'Do ustalenia',authorName:'Mateusz',authorId:'example-8',createdAt:new Date(Date.now()-3.6*DAY).toISOString(),replyCount:0,status:'open',sample:true}
];
const state = {posts:[],account:null,auth:null,ready:false,kind:'all',category:'all',query:'',city:'',detailId:null,busy:false};
let toastHandle;
const clean = str => String(str ?? '').trim();
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function fromStorage(key,def){try{const v=JSON.parse(localStorage.getItem(key));return Array.isArray(v)?v:def}catch{return def}}
function saveStorage(key,data){try{localStorage.setItem(key,JSON.stringify(data));return true}catch{toast('Nie można zapisać danych w tej przeglądarce.');return false}}
function toast(txt){$('toast').textContent=txt;$('toast').hidden=false;clearTimeout(toastHandle);toastHandle=setTimeout(()=>$('toast').hidden=true,5500)}
function identity(){return state.account?.idTokenClaims?.oid||state.account?.idTokenClaims?.sub||state.account?.localAccountId||state.account?.homeAccountId||''}
function userName(){return String(state.account?.idTokenClaims?.name||state.account?.name||state.account?.username||'Użytkownik').trim().slice(0,65)}
function userEmail(){const c=state.account?.idTokenClaims||{};return String(c.email||c.preferred_username||(Array.isArray(c.emails)?c.emails[0]:'')||state.account?.username||'').slice(0,130)}
function formatDate(iso){const diff=Date.now()-new Date(iso).getTime();if(!Number.isFinite(diff)||diff<0)return 'Dzisiaj';if(diff<3600000)return 'Przed chwilą';if(diff<DAY)return `${Math.floor(diff/3600000)} godz. temu`;if(diff<7*DAY)return `${Math.floor(diff/DAY)} dni temu`;return new Date(iso).toLocaleDateString('pl-PL')}
function initial(name){return String(name||'M').trim().charAt(0).toUpperCase()||'M'}
function scrollListings(){document.getElementById('ogloszenia').scrollIntoView({behavior:'smooth'})}
function showAccount(){
 const el=$('accountContent');
 if(!state.account){el.innerHTML='<p class="help-note">Zaloguj się lub utwórz konto w Microsoft Entra, aby publikować ogłoszenia i odpowiadać na zgłoszenia.</p><div class="account-actions"><button type="button" class="button button-main" data-auth="login">Zaloguj się</button><button type="button" class="button button-outline" data-auth="signup">Utwórz konto</button></div>'}
 else{el.innerHTML=`<div class="account-info"><strong>${esc(userName())}</strong><small>${esc(userEmail())}</small><small>Konto Microsoft Entra External ID</small></div><div class="account-actions"><button type="button" class="button button-main" id="goMyPosts">Moje ogłoszenia</button><button type="button" class="button button-outline" id="doLogout">Wyloguj się</button></div>`; $('goMyPosts').addEventListener('click',()=>{closeDialog('accountDialog');setKind('mine');scrollListings()});$('doLogout').addEventListener('click',logout)}
 el.querySelectorAll('[data-auth]').forEach(el=>el.addEventListener('click',()=>login(el.dataset.auth)));
 openDialog('accountDialog');
}
function updateAuthUI(){$('accountBtnText').textContent=state.account?userName().split(' ')[0]:'Zaloguj się'}
async function login(mode='login'){
 closeAllDialogs();if(!state.auth){toast('Logowanie Microsoft jest niedostępne. Odśwież stronę lub sprawdź połączenie.');return}
 try{const req={scopes:['openid','profile','email']};if(mode==='signup')req.prompt='create';await state.auth.loginRedirect(req)}catch(e){toast('Nie udało się uruchomić logowania: '+(e.message||'błąd'))}
}
async function logout(){if(!state.auth)return;closeAllDialogs();try{await state.auth.logoutRedirect({account:state.account,postLogoutRedirectUri:cfg.redirectUri})}catch(e){toast('Wylogowanie nie powiodło się: '+e.message)}}
async function initAuth(){
 if(!window.msal?.PublicClientApplication){toast('Nie udało się załadować modułu logowania Microsoft.');return}
 try{
  state.auth=new msal.PublicClientApplication({auth:{clientId:cfg.clientId,authority:cfg.authority,knownAuthorities:[new URL(cfg.authority).hostname,`${cfg.tenantId}.ciamlogin.com`],redirectUri:cfg.redirectUri,postLogoutRedirectUri:cfg.redirectUri,navigateToLoginRequestUrl:false},cache:{cacheLocation:'sessionStorage',storeAuthStateInCookie:false}});
  const result=await state.auth.handleRedirectPromise();state.account=result?.account||state.auth.getAllAccounts()[0]||null;
  if(state.account)state.auth.setActiveAccount(state.account);updateAuthUI();
 }catch(e){console.error('MSAL:',e);toast('Logowanie Microsoft nie zostało zakończone. Sprawdź konfigurację aplikacji.')}
}
async function getAccessToken(){
 if(!state.account)throw Error('Zaloguj się, aby wykonać tę czynność.');
 if(!cfg.apiScope)throw Error('Nie skonfigurowano uprawnień Azure API.');
 const req={account:state.account,scopes:[cfg.apiScope]};
 try{return (await state.auth.acquireTokenSilent(req)).accessToken}
 catch(e){if(e instanceof msal.InteractionRequiredAuthError){await state.auth.acquireTokenRedirect(req);throw Error('Dokończ nadawanie uprawnień w Microsoft Entra.')}throw e}
}
async function apiCall(path,{method='GET',body,secured=false}={}){
 const headers={'Accept':'application/json'};
 if(body!==undefined)headers['Content-Type']='application/json';
 if(secured)headers.Authorization='Bearer '+await getAccessToken();
 const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),18000);
 try{const response=await fetch(cfg.apiBaseUrl.replace(/\/$/,'')+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body),signal:controller.signal});const data=await response.json().catch(()=>({}));if(!response.ok)throw Error(data.error||`Błąd serwera ${response.status}`);return data}
 finally{clearTimeout(timeout)}
}
async function loadPosts(){
 if(DEMO){state.posts=[...fromStorage(DEMO_POSTS_KEY,[]),...SAMPLE];renderPosts();return}
 try{const data=await apiCall('/posts');state.posts=Array.isArray(data.posts)?data.posts:[];renderPosts()}
 catch(e){state.posts=[];renderPosts();toast('Nie udało się pobrać ogłoszeń z Azure: '+e.message)}
}
function setKind(kind){if(kind==='mine'&&!state.account){showAccount();return}state.kind=kind;document.querySelectorAll('[data-kind]').forEach(b=>{const active=b.dataset.kind===kind;b.classList.toggle('active',active);b.setAttribute('aria-selected',String(active))});renderPosts()}
function filtered(){return state.posts.filter(p=>{
 if(state.kind==='mine'&&p.authorId!==identity())return false;
 if(state.kind==='need'&&p.kind!=='need')return false;
 if(state.kind==='offer'&&p.kind!=='offer')return false;
 if(state.category!=='all'&&p.category!==state.category)return false;
 const q=state.query.toLocaleLowerCase('pl');const city=state.city.toLocaleLowerCase('pl');
 return (!q||`${p.title} ${p.description} ${p.category} ${p.city}`.toLocaleLowerCase('pl').includes(q))&&(!city||String(p.city).toLocaleLowerCase('pl').includes(city))
 }).sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt))}
function postCard(p){const kind=p.kind==='offer'?'Oferuję pomoc':'Potrzebuję pomocy';const action=p.kind==='offer'?'Zobacz ofertę':'Zobacz zgłoszenie';return `<article class="listing-card"><div class="listing-card-head"><span class="listing-kind ${esc(p.kind)}">${esc(kind)}</span><span class="listing-time">${esc(formatDate(p.createdAt))}</span></div><div class="listing-body" data-open="${esc(p.id)}" role="button" tabindex="0" aria-label="Otwórz ${esc(p.title)}"><h3>${esc(p.title)}</h3><p>${esc(p.description)}</p><div class="listing-meta"><span>📍 ${esc(p.city)}</span><span>${CAT_ICON[p.category]||'🛠️'} ${esc(p.category)}</span>${p.budget?`<span>💰 ${esc(p.budget)}</span>`:''}</div></div><div class="listing-card-footer"><div class="listing-author"><span class="author-avatar">${esc(initial(p.authorName))}</span><strong>${esc(p.authorName||'Użytkownik')}</strong></div><button type="button" class="link-button" data-open="${esc(p.id)}">${action} →</button></div></article>`}
function renderPosts(){const posts=filtered();$('resultsCount').textContent=`${posts.length} ogłoszeń`;$('listingGrid').innerHTML=posts.map(postCard).join('');$('emptyState').hidden=posts.length>0;$('listingGrid').querySelectorAll('[data-open]').forEach(el=>{el.addEventListener('click',()=>openDetails(el.dataset.open));if(el.getAttribute('role')==='button')el.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();openDetails(el.dataset.open)}})})}
function resetFilters(){state.query='';state.city='';state.category='all';$('heroSearch').value='';$('heroCity').value='';$('feedSearch').value='';$('categorySelect').value='all';setKind('all')}
function openDialog(id){const dlg=$(id);if(!dlg.open)dlg.showModal()}
function closeDialog(id){const dlg=$(id);if(dlg.open)dlg.close()}
function closeAllDialogs(){['postDialog','detailsDialog','accountDialog'].forEach(closeDialog)}
function newPost(type='need'){
 if(!state.account){showAccount();toast('Zaloguj się, aby opublikować ogłoszenie.');return}
 $('postForm').reset();$('postForm').querySelector(`[name=kind][value=${type}]`).checked=true;openDialog('postDialog')
}
function readPostForm(form){const f=new FormData(form);return {kind:clean(f.get('kind')),title:clean(f.get('title')),description:clean(f.get('description')),category:clean(f.get('category')),city:clean(f.get('city')),budget:clean(f.get('budget')),urgency:clean(f.get('urgency'))}}
function validatePost(p){if(!['need','offer'].includes(p.kind))return 'Wybierz rodzaj ogłoszenia.';if(p.title.length<8||p.title.length>110)return 'Tytuł powinien mieć od 8 do 110 znaków.';if(!CATS.includes(p.category))return 'Wybierz kategorię.';if(p.city.length<2||p.city.length>80)return 'Wpisz nazwę miasta.';if(p.description.length<20||p.description.length>2500)return 'Opis powinien mieć od 20 do 2500 znaków.';if(p.budget.length>70)return 'Budżet jest za długi.';return null}
async function publish(e){e.preventDefault();if(state.busy)return;const payload=readPostForm(e.currentTarget);const bad=validatePost(payload);if(bad){toast(bad);return}state.busy=true;$('publishBtn').disabled=true;
 try{
  if(DEMO){const p={...payload,id:'local-'+crypto.randomUUID(),authorId:identity(),authorName:userName(),createdAt:new Date().toISOString(),replyCount:0,status:'open',local:true};const saved=fromStorage(DEMO_POSTS_KEY,[]);saved.unshift(p);if(!saveStorage(DEMO_POSTS_KEY,saved))return;toast('Zapisano w podglądzie tej przeglądarki. Inni użytkownicy nie widzą tego ogłoszenia.')}
  else await apiCall('/posts',{method:'POST',body:payload,secured:true});
  closeDialog('postDialog');resetFilters();await loadPosts();scrollListings();
 }catch(err){toast('Nie udało się opublikować: '+err.message)}finally{state.busy=false;$('publishBtn').disabled=false}
}
async function getReplies(id){if(DEMO){const replies=fromStorage(DEMO_REPLIES_KEY,[]).filter(r=>r.postId===id);const post=state.posts.find(p=>p.id===id);return post?.authorId===identity()?replies:replies.filter(r=>r.authorId===identity())}return (await apiCall(`/posts/${encodeURIComponent(id)}/responses`,{secured:true})).responses||[]}
async function openDetails(id){const p=state.posts.find(x=>x.id===id);if(!p)return;state.detailId=p.id;const isOwner=!!state.account&&p.authorId===identity();const kind=p.kind==='offer'?'Oferuję pomoc':'Potrzebuję pomocy';$('detailsContent').innerHTML=`<span class="listing-kind ${esc(p.kind)}">${kind}</span><h2 class="detail-title" id="detailsTitle">${esc(p.title)}</h2><div class="detail-chips"><span>📍 ${esc(p.city)}</span><span>${CAT_ICON[p.category]||'🛠️'} ${esc(p.category)}</span>${p.budget?`<span>💰 ${esc(p.budget)}</span>`:''}<span>⏱ ${esc(p.urgency||'Do ustalenia')}</span></div><p class="detail-text">${esc(p.description)}</p><div class="detail-author"><span class="author-avatar">${esc(initial(p.authorName))}</span><div><strong>${esc(p.authorName)}</strong><small>${esc(formatDate(p.createdAt))}${p.status==='closed'?' • Ogłoszenie zamknięte':''}</small></div></div>`;
 const area=$('responsesArea');area.innerHTML='';openDialog('detailsDialog');
 if(p.sample){area.innerHTML='<p class="help-note">To przykładowe ogłoszenie prezentujące wygląd serwisu. Nie pochodzi od rzeczywistej osoby i nie można wysłać do niej odpowiedzi.</p>';return}
 if(isOwner){
  area.innerHTML='<h3>Odpowiedzi na ogłoszenie</h3><p class="help-note">Odpowiedzi widzisz tylko Ty jako autor. Możesz rozpocząć prywatną rozmowę z każdą osobą, która odpowiedziała.</p><div id="ownerReplies">Wczytywanie…</div>'+(p.status!=='closed'?'<button class="button button-outline" type="button" id="closePost">Oznacz jako zakończone</button>':'');
  try{
   const list=await getReplies(p.id);
   $('ownerReplies').innerHTML=list.length?list.map(r=>`<article class="response-card"><strong>${esc(r.authorName||'Użytkownik')}</strong><p>${esc(r.message)}</p><small>${esc(formatDate(r.createdAt))}</small><br><button type="button" class="link-button" data-thread="${esc(r.id)}">Otwórz rozmowę →</button></article>`).join(''):'<p class="help-note">Nie ma jeszcze odpowiedzi na to ogłoszenie.</p>';
   $('ownerReplies').querySelectorAll('[data-thread]').forEach(btn=>btn.addEventListener('click',()=>openThread(p,btn.dataset.thread)));
  }catch(err){$('ownerReplies').textContent='Nie udało się pobrać odpowiedzi: '+err.message}
  $('closePost')?.addEventListener('click',()=>closePost(p));return;
 }
 if(!state.account){area.innerHTML='<h3>Skontaktuj się z autorem</h3><p class="help-note">Aby odpowiedzieć, zaloguj się na konto MechMaster.</p><button type="button" class="button button-main" id="detailLogin">Zaloguj się</button>';$('detailLogin').addEventListener('click',()=>login());return}
 try{
  const mine=await getReplies(p.id);
  if(mine.length){area.innerHTML='<h3>Twoja odpowiedź</h3><p class="help-note">Twoja propozycja została wysłana. Kontynuuj prywatną rozmowę z autorem.</p><button class="button button-main" id="myThread" type="button">Otwórz rozmowę →</button>';$('myThread').addEventListener('click',()=>openThread(p,identity()));return}
 }catch(e){toast('Nie udało się sprawdzić Twojej rozmowy: '+e.message)}
 if(p.status==='closed'){area.innerHTML='<p class="help-note">Ogłoszenie jest zakończone. Nie można wysyłać nowych propozycji.</p>';return}
 area.innerHTML=`<h3>${p.kind==='offer'?'Zapytaj o ofertę':'Zaproponuj pomoc'}</h3><form class="reply-form" id="replyForm"><label for="replyMessage" class="help-note">Twoją wiadomość zobaczy tylko autor ogłoszenia. Potem będziecie mogli kontynuować rozmowę tutaj.</label><textarea id="replyMessage" name="message" required minlength="10" maxlength="1200" placeholder="Napisz, jak możesz pomóc, lub o co chcesz zapytać..."></textarea><button class="button button-main" id="replySubmit" type="submit">Wyślij wiadomość ↗</button></form>`;
 $('replyForm').addEventListener('submit',e=>sendReply(e,p));

}
async function openThread(p,respondentId){
 const area=$('responsesArea');
 area.innerHTML='<h3>Prywatna rozmowa</h3><p class="help-note">Wiadomości w tej rozmowie widzi tylko autor ogłoszenia i osoba, która na nie odpowiedziała.</p><div id="threadMessages">Wczytywanie…</div><form id="threadForm" class="reply-form"><textarea id="threadMessage" minlength="10" maxlength="1200" required placeholder="Napisz wiadomość..."></textarea><button class="button button-main" id="threadSend" type="submit">Wyślij wiadomość →</button></form><button class="link-button" type="button" id="threadBack">← Wróć do ogłoszenia</button>';
 $('threadBack').addEventListener('click',()=>openDetails(p.id));
 try{
  let messages;
  if(DEMO){const first=fromStorage(DEMO_REPLIES_KEY,[]).find(r=>r.postId===p.id&&r.authorId===respondentId);messages=[...(first?[{id:'initial',authorId:respondentId,authorName:first.authorName,message:first.message,createdAt:first.createdAt}]:[]),...fromStorage(DEMO_MESSAGES_KEY,[]).filter(m=>m.postId===p.id&&m.respondentId===respondentId)];}
  else messages=(await apiCall(`/posts/${encodeURIComponent(p.id)}/responses/${encodeURIComponent(respondentId)}/messages`,{secured:true})).messages||[];
  $('threadMessages').innerHTML=messages.length?messages.map(m=>`<article class="response-card"><strong>${m.authorId===identity()?'Ty':esc(m.authorName||'Użytkownik')}</strong><p>${esc(m.message)}</p><small>${esc(formatDate(m.createdAt))}</small></article>`).join(''):'<p class="help-note">Brak wiadomości.</p>';
 }catch(err){$('threadMessages').textContent='Nie udało się pobrać rozmowy: '+err.message}
 $('threadForm').addEventListener('submit',async e=>{
  e.preventDefault();if(state.busy)return;
  const message=clean($('threadMessage').value);if(message.length<10||message.length>1200){toast('Wiadomość musi mieć od 10 do 1200 znaków.');return}
  state.busy=true;$('threadSend').disabled=true;
  try{
   if(DEMO){const saved=fromStorage(DEMO_MESSAGES_KEY,[]);saved.push({id:crypto.randomUUID(),postId:p.id,respondentId,authorId:identity(),authorName:userName(),message,createdAt:new Date().toISOString()});if(!saveStorage(DEMO_MESSAGES_KEY,saved))return;toast('Wiadomość zapisana wyłącznie w przeglądarce (podgląd).')}
   else{await apiCall(`/posts/${encodeURIComponent(p.id)}/responses/${encodeURIComponent(respondentId)}/messages`,{method:'POST',body:{message},secured:true});toast('Wiadomość wysłana.')}
   await openThread(p,respondentId);
  }catch(err){toast('Nie udało się wysłać wiadomości: '+err.message)}finally{state.busy=false;if($('threadSend'))$('threadSend').disabled=false}
 });
}

async function sendReply(e,p){e.preventDefault();if(state.busy)return;const message=clean($('replyMessage').value);if(message.length<10||message.length>1200){toast('Wiadomość powinna mieć od 10 do 1200 znaków.');return}state.busy=true;$('replySubmit').disabled=true;
 try{if(DEMO){const replies=fromStorage(DEMO_REPLIES_KEY,[]);if(replies.some(r=>r.postId===p.id&&r.authorId===identity()))throw Error('Odpowiedź na to ogłoszenie została już wysłana w tym podglądzie.');replies.push({id:crypto.randomUUID(),postId:p.id,authorId:identity(),authorName:userName(),message,createdAt:new Date().toISOString()});if(!saveStorage(DEMO_REPLIES_KEY,replies))return;toast('Wiadomość zapisana tylko w tej przeglądarce (tryb demonstracyjny).')}else{await apiCall(`/posts/${encodeURIComponent(p.id)}/responses`,{method:'POST',body:{message},secured:true});toast('Wiadomość wysłana do autora ogłoszenia.')}closeDialog('detailsDialog');await loadPosts()}
 catch(err){toast('Wysłanie nie powiodło się: '+err.message)}finally{state.busy=false;if($('replySubmit'))$('replySubmit').disabled=false}
}
async function closePost(p){if(!state.account||p.authorId!==identity())return;if(!confirm('Oznaczyć ogłoszenie jako zakończone?'))return;try{if(DEMO){const posts=fromStorage(DEMO_POSTS_KEY,[]);const item=posts.find(x=>x.id===p.id);if(item)item.status='closed';saveStorage(DEMO_POSTS_KEY,posts)}else{await apiCall(`/posts/${encodeURIComponent(p.id)}`,{method:'PATCH',body:{status:'closed'},secured:true})}closeDialog('detailsDialog');await loadPosts();toast('Ogłoszenie zostało zamknięte.')}catch(e){toast('Błąd: '+e.message)}}
function wireEvents(){
 $('year').textContent=new Date().getFullYear();$('accountBtn').addEventListener('click',showAccount);$('mobileLogin').addEventListener('click',showAccount);
 $('mobileMenuBtn').addEventListener('click',()=>{const open=$('mobileLinks').hidden;$('mobileLinks').hidden=!open;$('mobileMenuBtn').setAttribute('aria-expanded',String(open))});$('mobileLinks').querySelectorAll('a').forEach(a=>a.addEventListener('click',()=>$('mobileLinks').hidden=true));
 document.querySelectorAll('[data-new]').forEach(btn=>btn.addEventListener('click',()=>newPost()));document.querySelectorAll('[data-new-offer]').forEach(btn=>btn.addEventListener('click',()=>newPost('offer')));
 document.querySelectorAll('[data-close]').forEach(btn=>btn.addEventListener('click',()=>closeDialog(btn.closest('dialog').id)));document.querySelectorAll('dialog').forEach(d=>d.addEventListener('click',e=>{if(e.target===d)d.close()}));
 $('goListings').addEventListener('click',scrollListings);$('postForm').addEventListener('submit',publish);
 document.querySelectorAll('[data-kind]').forEach(btn=>btn.addEventListener('click',()=>setKind(btn.dataset.kind)));
 document.querySelectorAll('[data-category]').forEach(btn=>btn.addEventListener('click',()=>{state.category=btn.dataset.category;$('categorySelect').value=state.category;setKind('all');scrollListings()}));
 $('categorySelect').addEventListener('change',e=>{state.category=e.target.value;renderPosts()});
 $('feedSearch').addEventListener('input',e=>{state.query=clean(e.target.value);renderPosts()});
 $('heroSearchButton').addEventListener('click',()=>{state.query=clean($('heroSearch').value);state.city=clean($('heroCity').value);$('feedSearch').value=state.query;renderPosts();scrollListings()});
 $('heroSearch').addEventListener('keydown',e=>{if(e.key==='Enter')$('heroSearchButton').click()});$('heroCity').addEventListener('keydown',e=>{if(e.key==='Enter')$('heroSearchButton').click()});
 $('resetFilters').addEventListener('click',resetFilters);$('emptyReset').addEventListener('click',resetFilters);
 if(DEMO){$('modeNote').hidden=false;$('modeNoteText').textContent='WERSJA POKAZOWA • Przykładowe ogłoszenia. Nowe zgłoszenia i odpowiedzi zapisują się tylko w Twojej przeglądarce. Aby udostępnić je wszystkim, podłącz Azure Functions API.'}
}
(async()=>{wireEvents();renderPosts();await initAuth();await loadPosts()})();
