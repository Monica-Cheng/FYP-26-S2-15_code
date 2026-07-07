import React, { useState } from 'react';
import { db } from '../firebase';
import { doc, setDoc } from 'firebase/firestore';

const defaultSettings = {
  xpPerGymSession: 100,
  xpPerCardioSession: 80,
  xpPerStreak: 20,
  maxDailyXP: 300,
  compressAvailable: true,
  breakModeAvailable: true,
  freeTierAIMessages: 10,
  premiumPrice: 9.99,
};

function SettingRow({ label, sub, children }) {
  return (
    <div style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '16px 0', borderBottom: '1px solid #f0f0f0',
    }}>
      <div>
        <div style={{ fontSize: '14px', fontWeight: '500' }}>{label}</div>
        {sub && <div style={{ fontSize: '12px', color: '#aaa', marginTop: '2px' }}>{sub}</div>}
      </div>
      {children}
    </div>
  );
}

function Settings() {
  const [settings, setSettings] = useState(defaultSettings);
  const [saved, setSaved] = useState(false);
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    setSaving(true);
    try {
      await setDoc(doc(db, 'adminSettings', 'global'), settings);
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (err) {
      console.error(err);
    }
    setSaving(false);
  };

  const inputStyle = {
    padding: '8px 12px', borderRadius: '8px', border: '1px solid #ddd',
    fontSize: '14px', width: '100px', textAlign: 'right', outline: 'none',
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
        <h1 style={{ fontSize: '24px', fontWeight: '700' }}>Settings</h1>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          {saved && <span style={{ fontSize: '13px', color: '#1a9e6a' }}>✓ Saved successfully</span>}
          <button
            onClick={handleSave}
            disabled={saving}
            style={{
              padding: '10px 24px', borderRadius: '8px', border: 'none',
              backgroundColor: '#6c63ff', color: 'white', fontSize: '14px', fontWeight: '500',
            }}
          >
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
        </div>
      </div>
      <p style={{ color: '#888', fontSize: '14px', marginBottom: '32px' }}>Configure platform rules and gamification</p>

      <div style={{ backgroundColor: 'white', borderRadius: '12px', padding: '24px', marginBottom: '24px' }}>
        <h2 style={{ fontSize: '16px', fontWeight: '600', marginBottom: '4px' }}>XP & Gamification</h2>
        <p style={{ fontSize: '13px', color: '#aaa', marginBottom: '16px' }}>Control how users earn XP points</p>

        <SettingRow label="XP per gym session" sub="Awarded on session completion">
          <input type="number" style={inputStyle} value={settings.xpPerGymSession}
            onChange={e => setSettings(p => ({ ...p, xpPerGymSession: Number(e.target.value) }))} />
        </SettingRow>
        <SettingRow label="XP per cardio session" sub="Awarded on cardio completion">
          <input type="number" style={inputStyle} value={settings.xpPerCardioSession}
            onChange={e => setSettings(p => ({ ...p, xpPerCardioSession: Number(e.target.value) }))} />
        </SettingRow>
        <SettingRow label="XP per streak day" sub="Bonus XP for maintaining streaks">
          <input type="number" style={inputStyle} value={settings.xpPerStreak}
            onChange={e => setSettings(p => ({ ...p, xpPerStreak: Number(e.target.value) }))} />
        </SettingRow>
        <SettingRow label="Max daily XP cap" sub="Maximum XP a user can earn per day">
          <input type="number" style={inputStyle} value={settings.maxDailyXP}
            onChange={e => setSettings(p => ({ ...p, maxDailyXP: Number(e.target.value) }))} />
        </SettingRow>
      </div>

      <div style={{ backgroundColor: 'white', borderRadius: '12px', padding: '24px', marginBottom: '24px' }}>
        <h2 style={{ fontSize: '16px', fontWeight: '600', marginBottom: '4px' }}>Adaptive Features</h2>
        <p style={{ fontSize: '13px', color: '#aaa', marginBottom: '16px' }}>Toggle core adaptive workout features</p>

        <SettingRow label="Compress workout" sub="Allow users to shorten sessions">
          <input type="checkbox" checked={settings.compressAvailable}
            onChange={e => setSettings(p => ({ ...p, compressAvailable: e.target.checked }))}
            style={{ width: '18px', height: '18px', cursor: 'pointer' }} />
        </SettingRow>
        <SettingRow label="Break mode" sub="Allow users to pause their plan">
          <input type="checkbox" checked={settings.breakModeAvailable}
            onChange={e => setSettings(p => ({ ...p, breakModeAvailable: e.target.checked }))}
            style={{ width: '18px', height: '18px', cursor: 'pointer' }} />
        </SettingRow>
      </div>

      <div style={{ backgroundColor: 'white', borderRadius: '12px', padding: '24px' }}>
        <h2 style={{ fontSize: '16px', fontWeight: '600', marginBottom: '4px' }}>Subscription</h2>
        <p style={{ fontSize: '13px', color: '#aaa', marginBottom: '16px' }}>Free vs premium tier limits</p>

        <SettingRow label="Free tier AI messages/month" sub="Cap for free users on WiseCoach chat">
          <input type="number" style={inputStyle} value={settings.freeTierAIMessages}
            onChange={e => setSettings(p => ({ ...p, freeTierAIMessages: Number(e.target.value) }))} />
        </SettingRow>
        <SettingRow label="Premium price (USD/month)" sub="Monthly subscription price">
          <input type="number" style={inputStyle} value={settings.premiumPrice}
            onChange={e => setSettings(p => ({ ...p, premiumPrice: Number(e.target.value) }))} />
        </SettingRow>
      </div>
    </div>
  );
}

export default Settings;