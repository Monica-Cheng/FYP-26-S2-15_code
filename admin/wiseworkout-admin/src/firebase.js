import { initializeApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";
import { getAuth } from "firebase/auth";

const firebaseConfig = {
  apiKey: "AIzaSyALWY9MoYLP0uyIrKLY5_-k4MfGIkw_czM",
  authDomain: "wiseworkout-fyp2615.firebaseapp.com",
  projectId: "wiseworkout-fyp2615",
  storageBucket: "wiseworkout-fyp2615.firebasestorage.app",
  messagingSenderId: "774192612607",
  appId: "1:774192612607:web:cd272fd5af8b6eb5a178ca"
};

const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const auth = getAuth(app);