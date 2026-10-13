// Sends www.agry.dev to the bare domain; everything else is a static asset.
export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		if (url.hostname === "www.agry.dev") {
			url.hostname = "agry.dev";
			return Response.redirect(url.toString(), 301);
		}
		return env.ASSETS.fetch(request);
	},
};
