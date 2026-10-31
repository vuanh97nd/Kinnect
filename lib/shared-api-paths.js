// Routes whose account/chat state has one PostgreSQL authority on both backends.
export function sharedApiPath(path,method='GET') {
 return ['/api/login','/api/register','/api/logout','/api/conversations','/api/notifications','/api/groups'].includes(path)
  || path==='/api/me'&&method==='GET'
  || /^\/api\/users\/[^/]+\/messages$/.test(path)
  || /^\/api\/users\/[^/]+\/block$/.test(path)
  || /^\/api\/groups\/[^/]+(?:\/messages)?$/.test(path);
}
