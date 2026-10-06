const ORG = 'gobeaver';

export interface Contributor {
	login: string;
	url: string;
	avatar: string;
	contributions: number;
}

interface GitHubRepo {
	name: string;
	fork: boolean;
	archived: boolean;
}

interface GitHubContributor {
	login: string;
	html_url: string;
	avatar_url: string;
	type: string;
	contributions: number;
}

// Build-time list. Memoized so the dev server doesn't re-hit the API on every page load.
let cached: Promise<Contributor[]> | undefined;

export function getContributors(): Promise<Contributor[]> {
	cached ??= fetchContributors(process.env.GITHUB_TOKEN).catch((err) => {
		console.warn(`[contributors] GitHub fetch failed, rendering fallback: ${err}`);
		return [];
	});
	return cached;
}

// Shared by the build (with an optional token) and the browser refresh (without).
export async function fetchContributors(token?: string): Promise<Contributor[]> {
	const github = <T,>(path: string) => request<T>(path, token);
	const repos = await github<GitHubRepo[]>(`/orgs/${ORG}/repos?type=public&per_page=100`);
	const lists = await Promise.all(
		repos
			.filter((r) => !r.fork && !r.archived)
			.map((r) => github<GitHubContributor[]>(`/repos/${ORG}/${r.name}/contributors?per_page=100`)),
	);

	const byLogin = new Map<string, Contributor>();
	for (const c of lists.flat()) {
		if (c.type === 'Bot') continue;
		const existing = byLogin.get(c.login);
		if (existing) {
			existing.contributions += c.contributions;
		} else {
			byLogin.set(c.login, {
				login: c.login,
				url: c.html_url,
				avatar: c.avatar_url,
				contributions: c.contributions,
			});
		}
	}
	return [...byLogin.values()].sort((a, b) => b.contributions - a.contributions);
}

async function request<T>(path: string, token?: string): Promise<T> {
	const res = await fetch(`https://api.github.com${path}`, {
		headers: {
			Accept: 'application/vnd.github+json',
			...(token && { Authorization: `Bearer ${token}` }),
		},
	});
	if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${path}`);
	// 204 No Content: an empty repo has no contributors.
	if (res.status === 204) return [] as T;
	return res.json() as Promise<T>;
}

export const label = (c: Contributor) =>
	`${c.login} · ${c.contributions} commit${c.contributions === 1 ? '' : 's'}`;
