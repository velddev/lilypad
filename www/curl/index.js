// `curl lilypad.to` comes in over http, and curl won't follow the redirect to https.
// So it gets the https answer here, which is the install script (functions/_middleware.ts).
export default {
  fetch(request) {
    if (!/^(curl|wget)\//i.test(request.headers.get("user-agent") ?? "")) return fetch(request);
    return fetch("https://lilypad.to/", request);
  },
};
