begin;
revoke execute on function public.issue_expired_device_pairing(uuid,uuid,uuid) from service_role;
revoke execute on function public.reserve_expired_device_verification(uuid) from service_role;
revoke execute on function public.complete_expired_device_pairing(uuid,uuid,text) from authenticated;
commit;
