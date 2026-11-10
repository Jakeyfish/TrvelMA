// Identity always comes from the verified bearer token, never a supplied owner id.
export async function deleteOwnAccount({ token, password, confirmation }, deps) {
  if (!token || !password || confirmation !== 'DELETE') throw Error('CONFIRMATION_REQUIRED');
  const user = await deps.verifyToken(token);
  if (!user?.id || !user.email) throw Error('AUTH_REQUIRED');
  const verified = await deps.verifyPassword(user.email, password);
  if (verified?.id !== user.id) throw Error('PASSWORD_INVALID');
  const prefix = `${user.id}/`;
  const paths = await deps.listAssets(user.id);
  if (paths.some(path => !path.startsWith(prefix) || path.includes('/../'))) throw Error('UNSAFE_ASSET_PATH');
  for (let offset = 0; offset < paths.length; offset += 100) await deps.removeAssets(paths.slice(offset, offset + 100));
  await deps.deleteUser(user.id);
  return { deleted: true };
}
