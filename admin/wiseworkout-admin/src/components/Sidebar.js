import React from 'react';

const menuItems = [
  { id: 'dashboard', label: 'Dashboard', icon: '📊' },
  { id: 'users', label: 'Users', icon: '👥' },
  { id: 'businessPartners', label: 'Business Partners', icon: '🤝' },
  { id: 'exercises', label: 'Exercises', icon: '💪' },
  { id: 'settings', label: 'Settings', icon: '⚙️' },
  { id: 'analytics', label: 'Analytics', icon: '📈' },
  { id: 'challenges', label: 'Challenges', icon: '🏆' },
];

function Sidebar({ currentPage, setCurrentPage, onLogout }) {
  return (
    <div style={{
      width: '220px',
      minHeight: '100vh',
      backgroundColor: '#1a1a2e',
      color: 'white',
      display: 'flex',
      flexDirection: 'column',
      padding: '24px 0',
    }}>
      <div style={{ padding: '0 24px 32px' }}>
        <div style={{ fontSize: '13px', color: '#a0a0b0', marginBottom: '4px' }}>WiseWorkout</div>
        <div style={{ fontSize: '16px', fontWeight: '600' }}>Admin Portal</div>
      </div>

      <div style={{ flex: 1 }}>
        {menuItems.map(item => (
          <div
            key={item.id}
            onClick={() => setCurrentPage(item.id)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '12px',
              padding: '12px 24px',
              cursor: 'pointer',
              backgroundColor: currentPage === item.id ? '#16213e' : 'transparent',
              borderLeft: currentPage === item.id ? '3px solid #6c63ff' : '3px solid transparent',
              color: currentPage === item.id ? '#ffffff' : '#a0a0b0',
              fontSize: '14px',
            }}
          >
            <span>{item.icon}</span>
            <span>{item.label}</span>
          </div>
        ))}
      </div>

      <div
        onClick={onLogout}
        style={{
          padding: '12px 24px',
          cursor: 'pointer',
          color: '#ff6b6b',
          fontSize: '14px',
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
        }}
      >
        <span>🚪</span>
        <span>Sign out</span>
      </div>
    </div>
  );
}

export default Sidebar;