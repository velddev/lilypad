// `curl https://lilypad.to | sh` gets the install script; browsers get the site.
export const onRequest = async ({ request, next, env }) => {
  const agent = request.headers.get("user-agent") ?? "";
  if (new URL(request.url).pathname !== "/" || !/^(curl|wget)\//i.test(agent)) return next();
  const script = await env.ASSETS.fetch(new URL("/install.sh", request.url));
  return new Response(script.body, { headers: { "content-type": "text/plain; charset=utf-8" } });
};
