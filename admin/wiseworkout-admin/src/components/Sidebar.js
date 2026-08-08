import React from 'react';
import {
  BadgeCheck,
  BarChart3,
  ClipboardList,
  Dumbbell,
  FileText,
  Handshake,
  LayoutDashboard,
  LogOut,
  Megaphone,
  Settings,
  ShieldAlert,
  Trophy,
  Users,
} from 'lucide-react';

const menuSections = [
  {
    label: 'Overview',
    items: [
      { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
      { id: 'analytics', label: 'Analytics', icon: BarChart3 },
    ],
  },
  {
    label: 'Management',
    items: [
      { id: 'users', label: 'Users', icon: Users },
      { id: 'businessPartners', label: 'Business Partners', icon: Handshake },
    ],
  },
  {
    label: 'Content',
    items: [
      { id: 'exercises', label: 'Exercises', icon: Dumbbell },
      { id: 'plans', label: 'Plans', icon: ClipboardList },
      { id: 'challenges', label: 'Challenges', icon: Trophy },
      { id: 'posts', label: 'Posts', icon: FileText },
      { id: 'injuries', label: 'Injuries', icon: ShieldAlert },
      { id: 'badges', label: 'Badges', icon: BadgeCheck },
    ],
  },
  {
    label: 'Communication',
    items: [{ id: 'broadcasts', label: 'Broadcasts', icon: Megaphone }],
  },
  {
    label: 'System',
    items: [{ id: 'settings', label: 'Settings', icon: Settings }],
  },
];

function Sidebar({ currentPage, setCurrentPage, onLogout }) {
  return (
    <aside className="wwa-sidebar">
      <div className="wwa-sidebar__brand">
        <div className="wwa-sidebar__eyebrow">WISEWORKOUT</div>
        <div className="wwa-sidebar__title">Admin Portal</div>
      </div>

      <nav className="wwa-sidebar__nav" aria-label="Admin navigation">
        {menuSections.map((section) => (
          <div key={section.label} className="wwa-sidebar__section">
            <div className="wwa-sidebar__section-label">{section.label}</div>
            <div className="wwa-sidebar__items">
              {section.items.map((item) => {
                const Icon = item.icon;
                const isActive = currentPage === item.id;

                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setCurrentPage(item.id)}
                    className={`wwa-sidebar__item ${isActive ? 'is-active' : ''}`}
                    aria-current={isActive ? 'page' : undefined}
                  >
                    <Icon className="wwa-sidebar__icon" aria-hidden="true" strokeWidth={2} />
                    <span className="wwa-sidebar__item-label">{item.label}</span>
                  </button>
                );
              })}
            </div>
          </div>
        ))}
      </nav>

      <div className="wwa-sidebar__footer">
        <button type="button" onClick={onLogout} className="wwa-sidebar__item wwa-sidebar__item-signout">
          <LogOut className="wwa-sidebar__icon" aria-hidden="true" strokeWidth={2} />
          <span className="wwa-sidebar__item-label">Sign out</span>
        </button>
      </div>
    </aside>
  );
}

export default Sidebar;
