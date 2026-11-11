-- Emergency disable, retains audit/history. Run only under deployment authorization.
begin;
update admin_private.principals set enabled=false;
revoke execute on function public.admin_context(), public.admin_users(text,text,integer), public.admin_user_detail(text,uuid), public.admin_release_device(text,uuid,uuid,timestamptz,uuid,text), public.admin_set_entitlement(text,uuid,timestamptz,text,text,timestamptz,integer,uuid,text), public.admin_audit(text,integer) from authenticated;
commit;
-- Restore only named, reviewed principals and explicit function grants after diagnosis.
-- Never delete audit records or bulk-revert grants written after deployment.
