'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import BottomNav from '@/components/BottomNav';
import ThemeToggle from '@/components/ThemeToggle';
import styles from './profile.module.css';

export default function ProfilePage() {
    const [profile, setProfile] = useState(null);
    const [loading, setLoading] = useState(true);
    const [myPosts, setMyPosts] = useState([]);
    const router = useRouter();
    const supabase = createClient();

    useEffect(() => {
        fetchProfile();
        fetchMyPosts();
    }, []);

    const fetchProfile = async () => {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) {
            router.push('/auth');
            return;
        }

        const { data } = await supabase
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .single();

        if (data) {
            setProfile(data);
        }
        setLoading(false);
    };

    const fetchMyPosts = async () => {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) return;

        const { data } = await supabase
            .from('posts')
            .select('*')
            .eq('user_id', user.id)
            .in('status', ['active', 'pending'])
            .order('created_at', { ascending: false });

        setMyPosts(data || []);
    };

    const handleSignOut = async () => {
        await supabase.auth.signOut();
        router.push('/auth');
        router.refresh();
    };

    if (loading) {
        return (
            <div className={styles.page}>
                <div className={styles.loading}>
                    <div className={styles.spinner}></div>
                </div>
                <BottomNav />
            </div>
        );
    }

    return (
        <div className={styles.page}>
            <header className={styles.header}>
                <h1>👤 Profile</h1>
                <ThemeToggle />
            </header>

            <main className={styles.main}>
                {/* Profile Info - Read Only */}
                <div className={styles.card}>
                    <h2 className={styles.cardTitle}>Personal Information</h2>

                    <div className={styles.profileInfo}>
                        <div className={styles.infoRow}>
                            <span className={styles.infoLabel}>Full Name</span>
                            <span className={styles.infoValue}>{profile?.name || 'Not set'}</span>
                        </div>
                        <div className={styles.infoRow}>
                            <span className={styles.infoLabel}>University ID</span>
                            <span className={styles.infoValue}>{profile?.student_id || 'Not set'}</span>
                        </div>
                        <div className={styles.infoRow}>
                            <span className={styles.infoLabel}>Phone Number</span>
                            <span className={styles.infoValue}>{profile?.phone || 'Not set'}</span>
                        </div>
                    </div>
                </div>

                {/* Stats */}
                <div className={styles.statsCard}>
                    <h3>Your Activity</h3>
                    <div className={styles.stats}>
                        <div className={styles.stat}>
                            <span className={styles.statValue}>{myPosts.length}</span>
                            <span className={styles.statLabel}>Active Posts</span>
                        </div>
                        <div className={styles.stat}>
                            <span className={styles.statValue}>{5 - myPosts.length}</span>
                            <span className={styles.statLabel}>Posts Left</span>
                        </div>
                    </div>
                </div>

                {/* Sign Out */}
                <button onClick={handleSignOut} className={styles.signOutBtn}>
                    🚪 Sign Out
                </button>
            </main>

            <BottomNav />
        </div>
    );
}
