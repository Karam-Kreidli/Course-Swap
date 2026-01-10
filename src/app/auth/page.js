'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import { createClient } from '@/lib/supabase/client';
import ThemeToggle from '@/components/ThemeToggle';
import styles from './auth.module.css';

export default function AuthPage() {
    const [isLogin, setIsLogin] = useState(true);
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    // Profile fields for signup
    const [name, setName] = useState('');
    const [studentId, setStudentId] = useState('');
    const [phone, setPhone] = useState('');
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const router = useRouter();
    const supabase = createClient();

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError('');
        setLoading(true);

        try {
            if (isLogin) {
                // Login
                const { error } = await supabase.auth.signInWithPassword({
                    email,
                    password,
                });

                if (error) throw error;
                router.push('/');
                router.refresh();
            } else {
                // Signup - validate all fields
                if (!name.trim()) {
                    throw new Error('Please enter your full name');
                }

                // Validate student ID format: UYYSSXXXX
                const studentIdRegex = /^U\d{2}(10|20)\d{4}$/;
                if (!studentIdRegex.test(studentId)) {
                    throw new Error('Student ID must follow the format UYYSSXXXX (e.g., U2410xxxx for Fall 2024)');
                }

                // Validate phone format
                const phoneRegex = /^[\d\s\-\+\(\)]{10,}$/;
                if (!phoneRegex.test(phone)) {
                    throw new Error('Please enter a valid phone number');
                }

                // Check if University ID is already taken
                const { data: existingProfile } = await supabase
                    .from('profiles')
                    .select('student_id')
                    .eq('student_id', studentId)
                    .single();

                if (existingProfile) {
                    throw new Error('This University ID is already registered.wha');
                }

                if (password !== confirmPassword) {
                    throw new Error('Passwords do not match');
                }

                if (password.length < 6) {
                    throw new Error('Password must be at least 6 characters');
                }

                if (!email.includes('@')) {
                    throw new Error('Please enter a valid email address');
                }

                const { data, error } = await supabase.auth.signUp({
                    email,
                    password,
                });

                if (error) throw error;

                // Check if user already exists
                if (data?.user?.identities?.length === 0) {
                    throw new Error('An account with this email already exists. Please sign in instead.');
                }

                // Auto login after signup
                const { error: loginError } = await supabase.auth.signInWithPassword({
                    email,
                    password,
                });

                if (loginError) throw loginError;

                // Create/update profile with the provided info
                const { error: profileError } = await supabase
                    .from('profiles')
                    .update({
                        name: name.trim(),
                        student_id: studentId,
                        phone: phone.trim(),
                        email: email.trim(),
                    })
                    .eq('id', data.user.id);

                if (profileError) {
                    console.error('Profile update error:', profileError);
                }

                router.push('/');
                router.refresh();
            }
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    const toggleMode = () => {
        setIsLogin(!isLogin);
        setError('');
        setEmail('');
        setPassword('');
        setConfirmPassword('');
        setName('');
        setStudentId('');
        setPhone('');
    };

    return (
        <div className={styles.container}>
            <div className={styles.card}>
                <div className={styles.themeToggleWrapper}>
                    <ThemeToggle />
                </div>
                {/* Logo */}
                <div className={styles.logoWrapper}>
                    <Image src="/logo.png" alt="Course Swap" width={72} height={72} className={styles.logo} />
                    <h1 className={styles.title}>Course Swap</h1>
                    <p className={styles.subtitle}>University course section exchange</p>
                </div>

                {/* Form */}
                <form onSubmit={handleSubmit} className={styles.form}>
                    <div className={styles.formGroup}>
                        <label className={styles.label}>Email</label>
                        <input
                            type="email"
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            className={styles.input}
                            placeholder="Enter your email"
                            required
                            disabled={loading}
                        />
                    </div>

                    <div className={styles.formGroup}>
                        <label className={styles.label}>Password</label>
                        <input
                            type="password"
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            className={styles.input}
                            placeholder="Enter password"
                            required
                            disabled={loading}
                        />
                    </div>

                    {!isLogin && (
                        <div className={styles.formGroup}>
                            <label className={styles.label}>Confirm Password</label>
                            <input
                                type="password"
                                value={confirmPassword}
                                onChange={(e) => setConfirmPassword(e.target.value)}
                                className={styles.input}
                                placeholder="Confirm password"
                                required
                                disabled={loading}
                            />
                        </div>
                    )}

                    {/* Profile fields for signup */}
                    {!isLogin && (
                        <>
                            <div className={styles.formGroup}>
                                <label className={styles.label}>Full Name</label>
                                <input
                                    type="text"
                                    value={name}
                                    onChange={(e) => setName(e.target.value)}
                                    className={styles.input}
                                    placeholder="Enter your full name"
                                    required
                                    disabled={loading}
                                />
                            </div>

                            <div className={styles.formGroup}>
                                <label className={styles.label}>University ID</label>
                                <input
                                    type="text"
                                    value={studentId}
                                    onChange={(e) => setStudentId(e.target.value.toUpperCase())}
                                    className={styles.input}
                                    placeholder="e.g., U24101234"
                                    required
                                    disabled={loading}
                                />
                            </div>

                            <div className={styles.formGroup}>
                                <label className={styles.label}>Phone Number</label>
                                <input
                                    type="tel"
                                    value={phone}
                                    onChange={(e) => setPhone(e.target.value)}
                                    className={styles.input}
                                    placeholder="Enter your phone number"
                                    required
                                    disabled={loading}
                                />
                            </div>
                        </>
                    )}

                    {error && <div className={styles.error}>{error}</div>}

                    <button type="submit" className={styles.submitBtn} disabled={loading}>
                        {loading ? (
                            <span className={styles.spinner} />
                        ) : (
                            isLogin ? 'Sign In' : 'Create Account'
                        )}
                    </button>
                </form>

                {/* Toggle */}
                <div className={styles.toggle}>
                    <span className={styles.toggleText}>
                        {isLogin ? "Don't have an account?" : 'Already have an account?'}
                    </span>
                    <button type="button" onClick={toggleMode} className={styles.toggleBtn} disabled={loading}>
                        {isLogin ? 'Sign Up' : 'Sign In'}
                    </button>
                </div>
            </div>
        </div>
    );
}
