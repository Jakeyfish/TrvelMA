-- Read-only runtime denial check. Leaves no persistent claims or application data.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{}',true);
do $$
begin
 begin
  perform public.admin_context();
 exception when insufficient_privilege then
  if sqlerrm='ADMIN_MFA_REQUIRED' then
   perform set_config('admin.test_result','MFA_DENIAL_CONFIRMED',true);
   return;
  end if;
  raise;
 end;
 raise exception 'EXPECTED_ADMIN_DENIAL';
end $$;
select current_setting('admin.test_result') as verification;
rollback;
