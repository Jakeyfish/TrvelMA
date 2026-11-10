import { createClient } from "npm:@supabase/supabase-js@2";
import { deleteOwnAccount } from "./core.mjs";
const headers={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,apikey,content-type","Access-Control-Allow-Methods":"POST,OPTIONS","Content-Type":"application/json","Cache-Control":"no-store"};
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
Deno.serve(async request=>{
 if(request.method==='OPTIONS')return new Response('ok',{headers});
 if(request.method!=='POST')return reply(405,{error:'Method not allowed'});
 const token=(request.headers.get('Authorization')||'').replace(/^Bearer /,'');
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_ANON_KEY'),adminKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!key||!adminKey)return reply(503,{error:'账号删除服务暂不可用，请稍后重试。'});
 try{
  const body=await request.json();
  if(typeof body.password!=='string'||body.password.length>1024||body.confirmation!=='DELETE')return reply(400,{error:'请输入当前密码并确认删除。'});
  const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const admin=createClient(url,adminKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const result=await deleteOwnAccount({token,password:body.password,confirmation:body.confirmation},{
   verifyToken:async(value:string)=>{const {data,error}=await client.auth.getUser(value);if(error)throw Error('AUTH_REQUIRED');return data.user;},
   verifyPassword:async(email:string,password:string)=>{const {data,error}=await client.auth.signInWithPassword({email,password});if(error)throw Error('PASSWORD_INVALID');return data.user;},
   listAssets:async(owner:string)=>{
    const bucket=admin.storage.from('account-assets'),queue=[owner],paths:string[]=[];
    while(queue.length){const folder=queue.shift()!;for(let offset=0;;offset+=100){const {data,error}=await bucket.list(folder,{limit:100,offset,sortBy:{column:'name',order:'asc'}});if(error)throw Error('ASSET_DELETE_FAILED');for(const item of data||[]){const path=`${folder}/${item.name}`;if(item.id)paths.push(path);else queue.push(path);}if((data||[]).length<100)break;}}
    return paths;
   },
   removeAssets:async(paths:string[])=>{const {error}=await admin.storage.from('account-assets').remove(paths);if(error)throw Error('ASSET_DELETE_FAILED');},
   deleteUser:async(id:string)=>{const {error}=await admin.auth.admin.deleteUser(id);if(error)throw Error('ACCOUNT_DELETE_FAILED');}
  });
  return reply(200,result);
 }catch(error){
  const code=error instanceof Error?error.message:'';
  if(code==='AUTH_REQUIRED'||code==='PASSWORD_INVALID')return reply(401,{error:'登录状态或当前密码不正确，请重新验证。'});
  return reply(400,{error:'删除未完成，请稍后重试。云端账号未确认删除前，请保留本机资料。'});
 }
});
