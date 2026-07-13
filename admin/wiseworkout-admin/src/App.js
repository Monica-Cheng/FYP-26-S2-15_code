import React, { useState } from 'react';
import Sidebar from './components/Sidebar';
import Dashboard from './pages/Dashboard';
import Users from './pages/Users';
import BusinessPartners from './pages/BusinessPartners';
import Exercises from './pages/Exercises';
import Settings from './pages/Settings';
import Analytics from './pages/Analytics';
import Challenges from './pages/Challenges';
import Login from './pages/Login';
import './App.css';

function App() {
  const [currentPage, setCurrentPage] = useState('dashboard');
  const [isLoggedIn, setIsLoggedIn] = useState(false);

  if (!isLoggedIn) {
    return <Login onLogin={() => setIsLoggedIn(true)} />;
  }

  const renderPage = () => {
    switch (currentPage) {
      case 'dashboard': return <Dashboard />;
      case 'users': return <Users />;
      case 'businessPartners': return <BusinessPartners />;
      case 'exercises': return <Exercises />;
      case 'settings': return <Settings />;
      case 'analytics': return <Analytics />;
      case 'challenges': return <Challenges />;
      default: return <Dashboard />;
    }
  };

  return (
    <div style={{ display: 'flex', minHeight: '100vh', backgroundColor: '#f5f5f5' }}>
      <Sidebar currentPage={currentPage} setCurrentPage={setCurrentPage} onLogout={() => setIsLoggedIn(false)} />
      <div style={{ flex: 1, padding: '32px', overflowY: 'auto' }}>
        {renderPage()}
      </div>
    </div>
  );
}

export default App;