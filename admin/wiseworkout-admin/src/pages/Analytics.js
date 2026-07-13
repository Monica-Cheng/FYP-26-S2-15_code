import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs } from 'firebase/firestore';

function Analytics() {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetch = async () => {
      try {
        const [usersSnap, plansSnap, exSnap, bpSnap] = await Promise.all([
          getDocs(collection(db, 'users')),
          getDocs(collection(db, 'plans')),
          getDocs(collection(db, 'exercises')),
          getDocs(collection(db, 'businessPartners')),
        ]);
        const users = usersSnap.docs.map(d => d.data());
        setStats({
          totalUsers: usersSnap.size,
          totalPlans: plansSnap.size,
          totalExercises: exSnap.size,
          totalBP: bpSnap.size,
          approvedBP: bpSnap.docs.filter(d => d.data().status === 'approved').length,
          pendingBP: bpSnap.docs.filter(d => d.data().status === 'pending').length,
          healthConnected: users.filter(u => u.healthConnected).length,
          onboarded: users.filter(u => u.onboardingComplete).length,
          suspended: users.filter(u => u.accountStatus === 'suspended').length,
          premiumUsers: users.filter(u => u.isPremium).length,
        });
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetch();
  }, []);

  if (loading) return <div style={{ color: '#888', fontSize: '14px' }}>Loading analytics...</div>;

  const cards = [
    { label: 'Total Users', value: stats.totalUsers, color: '#6c63ff' },
    { label: 'Onboarded Users', value: stats.onboarded, color: '#48cae4' },
    { label: 'Health Connected', value: stats.healthConnected, color: '#06d6a0' },
    { label: 'Premium Users', value: stats.premiumUsers, color: '#ffd166' },
    { label: 'Suspended Users', value: stats.suspended, color: '#ff6b6b' },
    { label: 'Total Plans', value: stats.totalPlans, color: '#6c63ff' },
    { label: 'Total Exercises', value: stats.totalExercises, color: '#06d6a0' },
    { label: 'Total Business Partners', value: stats.totalBP, color: '#48cae4' },
    { label: 'Approved BPs', value: stats.approvedBP, color: '#06d6a0' },
    { label: 'Pending BP Applications', value: stats.pendingBP, color: '#ff6b6b' },
  ];

  return (
    <div>
      <h1 style={{ fontSize: '24px', fontWeight: '700', marginBottom: '8px' }}>Analytics</h1>
      <p style={{ color: '#888', fontSize: '14px', marginBottom: '32px' }}>Platform overview — live from Firebase</p>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '16px' }}>
        {cards.map(card => (
          <div key={card.label} style={{
            backgroundColor: 'white', borderRadius: '12px', padding: '24px',
            minWidth: '200px', flex: '1', borderTop: `4px solid ${card.color}`,
          }}>
            <div style={{ fontSize: '13px', color: '#888', marginBottom: '8px' }}>{card.label}</div>
            <div style={{ fontSize: '32px', fontWeight: '700', color: '#1a1a2e' }}>{card.value}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default Analytics;