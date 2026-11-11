const cards={
 trips:{category:'接送机 · 预约管理',title:'接送机安排\n<em>一眼看清</em>',subtitle:'按日期查看行程，接送安排更从容',image:'trips.png',footer:'App 演示资料 · 设计样稿',number:'01'},
 flight:{category:'航班查询 · 信息留存',title:'航班信息\n<em>出发前有数</em>',subtitle:'起降时间、机场与航站楼，清晰呈现',image:'flight.png',footer:'航班查询需云端版 · 组件演示数据 · 设计样稿',number:'02'},
 finance:{category:'收支管理 · 旅行社对账',title:'收支与对账\n<em>心里有数</em>',subtitle:'汇总收入和支出，净收入清楚掌握',image:'finance.png',footer:'App 演示资料，不代表实际收益 · 设计样稿',number:'03'}
};
const kind=new URLSearchParams(location.search).get('card')||'trips';const c=cards[kind]||cards.trips;
document.querySelector('#canvas').classList.add(cards[kind]?kind:'trips');
for(const key of ['category','subtitle','footer','number'])document.getElementById(key).textContent=c[key];
document.getElementById('title').innerHTML=c.title;
document.getElementById('screen').src='assets/'+c.image;
