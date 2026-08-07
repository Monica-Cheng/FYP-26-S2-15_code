import React, { useState } from 'react';
import { auth } from '../firebase';
import { signInWithEmailAndPassword } from 'firebase/auth';

function Login({ onLogin }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async event => {
    event?.preventDefault();

    if (!email.trim() || !password) {
      setError('Enter both your email and password.');
      return;
    }

    setLoading(true);
    setError('');

    try {
      await signInWithEmailAndPassword(
        auth,
        email.trim(),
        password
      );

      onLogin();
    } catch (err) {
      console.error('Admin sign-in failed:', err);
      setError('Invalid email or password.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="ww-login-page">
      <style>{`
        .ww-login-page {
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 32px 20px;
          position: relative;
          overflow: hidden;
          background:
            radial-gradient(
              circle at 20% 20%,
              rgba(108, 99, 255, 0.22),
              transparent 34%
            ),
            radial-gradient(
              circle at 80% 80%,
              rgba(39, 202, 165, 0.12),
              transparent 30%
            ),
            #17182d;
        }

        .ww-login-page::before {
          content: '';
          position: absolute;
          inset: 0;
          background-image:
            linear-gradient(
              rgba(255, 255, 255, 0.015) 1px,
              transparent 1px
            ),
            linear-gradient(
              90deg,
              rgba(255, 255, 255, 0.015) 1px,
              transparent 1px
            );
          background-size: 48px 48px;
          pointer-events: none;
        }

        .ww-login-card {
          width: min(100%, 440px);
          position: relative;
          z-index: 1;
          padding: 42px;
          background: rgba(255, 255, 255, 0.98);
          border: 1px solid rgba(255, 255, 255, 0.8);
          border-radius: 20px;
          box-shadow:
            0 30px 80px rgba(0, 0, 0, 0.3),
            0 4px 18px rgba(0, 0, 0, 0.12);
        }

        .ww-login-brand-row {
          display: flex;
          align-items: center;
          gap: 12px;
          margin-bottom: 28px;
        }

        .ww-login-logo {
          width: 44px;
          height: 44px;
          border-radius: 13px;
          display: flex;
          align-items: center;
          justify-content: center;
          background:
            linear-gradient(
              135deg,
              #6c63ff,
              #8c7cff
            );
          color: white;
          font-size: 21px;
          box-shadow:
            0 10px 24px rgba(108, 99, 255, 0.3);
        }

        .ww-login-brand {
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: #7b8092;
        }

        .ww-login-heading {
          margin: 0;
          color: #171a28;
          font-size: 30px;
          line-height: 1.15;
          letter-spacing: -0.035em;
        }

        .ww-login-subtitle {
          margin: 9px 0 30px;
          color: #8a90a2;
          font-size: 14px;
          line-height: 1.55;
        }

        .ww-login-alert {
          margin-bottom: 18px;
          padding: 12px 14px;
          border: 1px solid #ffd3d3;
          border-radius: 10px;
          background: #fff1f1;
          color: #c53f3f;
          font-size: 13px;
        }

        .ww-login-field {
          margin-bottom: 18px;
        }

        .ww-login-label {
          display: block;
          margin-bottom: 7px;
          color: #454b5d;
          font-size: 13px;
          font-weight: 600;
        }

        .ww-login-input {
          width: 100%;
          height: 48px;
          padding: 0 14px;
          border: 1px solid #dfe2ea;
          border-radius: 13px;
          background: #fafbfe;
          color: #171a28;
          font-size: 14px;
          outline: none;
          transition:
            border-color 0.15s ease,
            box-shadow 0.15s ease,
            background 0.15s ease;
        }

        .ww-login-input::placeholder {
          color: #afb4c1;
        }

        .ww-login-input:focus {
          border-color: #746cff;
          background: #ffffff;
          box-shadow:
            0 0 0 4px rgba(108, 99, 255, 0.12);
        }

        .ww-login-button {
          width: 100%;
          height: 49px;
          margin-top: 8px;
          border: none;
          border-radius: 13px;
          background:
            linear-gradient(
              135deg,
              #655cff,
              #8176ff
            );
          color: white;
          font-size: 15px;
          font-weight: 700;
          cursor: pointer;
          box-shadow:
            0 12px 24px rgba(108, 99, 255, 0.26);
          transition:
            transform 0.15s ease,
            box-shadow 0.15s ease,
            opacity 0.15s ease;
        }

        .ww-login-button:hover:not(:disabled) {
          transform: translateY(-1px);
          box-shadow:
            0 15px 28px rgba(108, 99, 255, 0.32);
        }

        .ww-login-button:active:not(:disabled) {
          transform: translateY(0);
        }

        .ww-login-button:disabled {
          cursor: not-allowed;
          opacity: 0.65;
        }

        .ww-login-security {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 6px;
          margin-top: 22px;
          color: #9ba0ad;
          font-size: 12px;
        }

        @media (max-width: 520px) {
          .ww-login-card {
            padding: 32px 24px;
            border-radius: 17px;
          }

          .ww-login-heading {
            font-size: 27px;
          }
        }
      `}</style>

      <form
        className="ww-login-card"
        onSubmit={handleLogin}
      >
        <div className="ww-login-brand-row">
          <div className="ww-login-logo">W</div>

          <div className="ww-login-brand">
            WiseWorkout
          </div>
        </div>

        <h1 className="ww-login-heading">
          Admin Portal
        </h1>

        <p className="ww-login-subtitle">
          Sign in to manage users, content, plans and
          platform settings.
        </p>

        {error && (
          <div
            className="ww-login-alert"
            role="alert"
          >
            {error}
          </div>
        )}

        <div className="ww-login-field">
          <label
            className="ww-login-label"
            htmlFor="admin-email"
          >
            Email address
          </label>

          <input
            id="admin-email"
            className="ww-login-input"
            type="email"
            value={email}
            onChange={event =>
              setEmail(event.target.value)
            }
            placeholder="admin@wiseworkout.com"
            autoComplete="email"
            disabled={loading}
          />
        </div>

        <div className="ww-login-field">
          <label
            className="ww-login-label"
            htmlFor="admin-password"
          >
            Password
          </label>

          <input
            id="admin-password"
            className="ww-login-input"
            type="password"
            value={password}
            onChange={event =>
              setPassword(event.target.value)
            }
            placeholder="Enter your password"
            autoComplete="current-password"
            disabled={loading}
          />
        </div>

        <button
          className="ww-login-button"
          type="submit"
          disabled={loading}
        >
          {loading ? 'Signing in…' : 'Sign in'}
        </button>

        <div className="ww-login-security">
          <span>🔒</span>
          <span>Authorized administrator only</span>
        </div>
      </form>
    </div>
  );
}

export default Login;