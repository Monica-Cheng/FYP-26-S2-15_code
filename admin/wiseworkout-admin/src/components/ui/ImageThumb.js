import React, { useState } from 'react';
import { isValidImageUrl } from '../../utils/badgeUtils';

// Small thumbnail with a graceful fallback for missing/broken/invalid URLs —
// never attempts to fetch, download, or store the remote image itself.
function ImageThumb({ url, size = 40, icon = '🏅' }) {
  const [failed, setFailed] = useState(false);
  const showImage = isValidImageUrl(url) && !failed;

  if (!showImage) {
    return (
      <div style={{
        width: size, height: size, borderRadius: 8, background: '#f3f4f6',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: size * 0.45, flexShrink: 0,
      }}>
        {icon}
      </div>
    );
  }

  return (
    <img
      src={url}
      alt=""
      onError={() => setFailed(true)}
      style={{ width: size, height: size, borderRadius: 8, objectFit: 'cover', background: '#f3f4f6', flexShrink: 0 }}
    />
  );
}

export default ImageThumb;
