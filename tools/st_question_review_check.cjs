// Проверка автономной анкеты настоящими нажатиями в отдельном headless Chrome.
const { chromium } = require('C:/Users/rabin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const path = require('path');
const fs = require('fs');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',downloadsPath:path.resolve('build/batch28_stillion/downloads')});
 try{
 const context=await browser.newContext({viewport:{width:1280,height:720},acceptDownloads:true});
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('file:///'+path.resolve('build/stillion_questions_review.html').replaceAll('\\','/'));
 const initial=await page.locator('article').count();if(initial<120)throw Error('Банк не загружен');
 await page.locator('article').first().getByRole('button',{name:'Оставить',exact:true}).click();
 await page.locator('article').first().locator('textarea').fill('Проверено владельцем');
 await page.locator('article').nth(1).getByRole('button',{name:'Убрать',exact:true}).click();
 await page.locator('#state').selectOption('drop');if(await page.locator('article').count()!==1)throw Error('Фильтр решений');
 await page.locator('#state').selectOption('');await page.reload();
 if(await page.locator('article').first().locator('textarea').inputValue()!=='Проверено владельцем')throw Error('Сохранение');
 const downloadPromise=page.waitForEvent('download');await page.locator('#save').click();const download=await downloadPromise;
 await download.saveAs('build/batch28_stillion/browser-decisions.json');
 const data=JSON.parse(fs.readFileSync('build/batch28_stillion/browser-decisions.json','utf8'));
 if(data.decisions.length!==initial||data.decisions[0].choice!=='keep'||data.decisions[1].choice!=='drop')throw Error('Экспорт');
 await page.locator('#search').fill('несуществующий_вопрос_123');if(await page.locator('article').count()!==0)throw Error('Поиск');
 await page.locator('#search').fill('');await page.screenshot({path:'build/batch28_stillion/question-review.png'});
 if(errors.length)throw Error(errors.join('\n'));console.log(JSON.stringify({questions:initial,checks:7,errors:0}));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
