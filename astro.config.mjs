// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
			title: 'GoBeaver',
			description:
				'Composable Go building blocks for secure, scalable services — configkit, filekit, beaverkit, and the GoBeaver CLI.',
			social: [
				{
					icon: 'github',
					label: 'GitHub',
					href: 'https://github.com/gobeaver',
				},
			],
			sidebar: [
				{
					label: 'Introduction',
					autogenerate: { directory: 'intro' },
				},
				{
					label: 'Concepts',
					autogenerate: { directory: 'concepts' },
				},
				{
					label: 'configkit',
					badge: { text: 'stable-ish', variant: 'success' },
					link: '/configkit/',
				},
				{
					label: 'filekit',
					badge: { text: 'stable-ish', variant: 'success' },
					items: [
						{ label: 'Overview', slug: 'filekit' },
						{
							label: 'Drivers',
							autogenerate: { directory: 'filekit/drivers' },
						},
						{
							label: 'Validator',
							autogenerate: { directory: 'filekit/validator' },
						},
					],
				},
				{
					label: 'beaverkit',
					badge: { text: 'alpha', variant: 'caution' },
					autogenerate: { directory: 'beaverkit' },
				},
				{
					label: 'CLI',
					autogenerate: { directory: 'cli' },
				},
				{
					label: 'Recipes',
					autogenerate: { directory: 'recipes' },
				},
				{
					label: 'Contributing',
					autogenerate: { directory: 'contributing' },
				},
			],
		}),
	],
});
