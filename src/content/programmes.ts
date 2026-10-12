// Editable marketing content. Replace these placeholders with your real learning paths.
// Nothing here is read from the database yet; programmes arrive with the LMS phase.

export interface Programme {
  slug: string
  title: string
  summary: string
  skills: string[]
}

export const PROGRAMMES: Programme[] = [
  { slug: 'web', title: 'Web development', summary: 'Build and ship websites and web apps, from the first page to a deployed product.', skills: ['HTML and CSS', 'JavaScript and TypeScript', 'Vue', 'APIs and databases'] },
  { slug: 'data', title: 'Data and AI foundations', summary: 'Work with data, ask good questions of it, and understand how modern AI tools are built.', skills: ['Python', 'SQL', 'Data analysis', 'Machine learning basics'] },
  { slug: 'mobile', title: 'Mobile app development', summary: 'Design and build apps that run on phones, with real devices and real users in mind.', skills: ['App design', 'Cross-platform frameworks', 'Backend integration', 'Publishing'] },
  { slug: 'cyber', title: 'Cybersecurity essentials', summary: 'Learn how systems are attacked and defended, and build safe habits into everything you make.', skills: ['Networking basics', 'Secure coding', 'Threat awareness', 'Incident response'] },
  { slug: 'design', title: 'Product and UI design', summary: 'Turn ideas into clear, usable interfaces and test them with the people who will use them.', skills: ['User research', 'Wireframing', 'Interface design', 'Prototyping'] },
  { slug: 'career', title: 'Career and freelance launchpad', summary: 'Package your skills into a portfolio, find opportunities and start earning from your work.', skills: ['Portfolio building', 'Freelancing basics', 'Interview preparation', 'Working with clients'] },
]
