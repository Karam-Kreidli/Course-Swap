'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import styles from './BottomNav.module.css';

export default function BottomNav() {
    const pathname = usePathname();

    const navItems = [
        { href: '/', icon: '🏠', label: 'Home' },
        { href: '/matches', icon: '🔄', label: 'Matches' },
        { href: '/post', icon: '➕', label: 'Post' },
        { href: '/profile', icon: '👤', label: 'Profile' },
    ];

    return (
        <nav className={styles.bottomNav}>
            {navItems.map((item) => (
                <Link
                    key={item.href}
                    href={item.href}
                    className={`${styles.navItem} ${pathname === item.href ? styles.active : ''}`}
                >
                    <span className={styles.navIcon}>{item.icon}</span>
                    <span className={styles.navLabel}>{item.label}</span>
                </Link>
            ))}
        </nav>
    );
}
