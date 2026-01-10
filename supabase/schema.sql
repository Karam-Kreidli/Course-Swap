-- =====================================================
-- University Course Swap - Database Schema
-- =====================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- PROFILES TABLE
-- Extends Supabase auth.users with app-specific data
-- =====================================================
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
    username TEXT UNIQUE NOT NULL,
    name TEXT,
    student_id TEXT,
    phone TEXT,
    major TEXT,
    year TEXT,
    is_profile_complete BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for user lookups
CREATE INDEX idx_profiles_user_id ON profiles(user_id);
CREATE INDEX idx_profiles_username ON profiles(username);

-- =====================================================
-- COURSES TABLE
-- Course catalog with college code and name
-- =====================================================
CREATE TABLE courses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    course_id TEXT NOT NULL UNIQUE, -- 7-digit: XXXXYYY (4 college + 3 course)
    college_code TEXT NOT NULL,      -- First 4 digits
    course_number TEXT NOT NULL,     -- Last 3 digits
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for course lookups
CREATE INDEX idx_courses_course_id ON courses(course_id);
CREATE INDEX idx_courses_college_code ON courses(college_code);
CREATE INDEX idx_courses_name ON courses USING gin(to_tsvector('english', name));

-- =====================================================
-- SECTIONS TABLE
-- Section details for each course
-- =====================================================
CREATE TABLE sections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    course_id TEXT REFERENCES courses(course_id) ON DELETE CASCADE NOT NULL,
    section_num TEXT NOT NULL,       -- Section number (e.g., "01", "02")
    crn TEXT NOT NULL,               -- Course Registration Number
    class_time TEXT,                 -- Class schedule (e.g., "Sun/Tue 08:00-09:30")
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(course_id, section_num),
    UNIQUE(crn)
);

-- Index for section lookups
CREATE INDEX idx_sections_course_id ON sections(course_id);
CREATE INDEX idx_sections_crn ON sections(crn);

-- =====================================================
-- POSTS TABLE
-- All post types: swap, giveaway, request
-- =====================================================
CREATE TYPE post_type AS ENUM ('swap', 'giveaway', 'request');
CREATE TYPE post_status AS ENUM ('active', 'pending', 'completed', 'expired');

CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    post_type post_type NOT NULL,
    course_id TEXT REFERENCES courses(course_id) NOT NULL,
    have_section TEXT NOT NULL,  -- Section user has/is giving away
    want_section TEXT,           -- Section user wants (only for swap type)
    status post_status DEFAULT 'active',
    is_locked BOOLEAN DEFAULT FALSE, -- Locked during pending match
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for post queries
CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_course_id ON posts(course_id);
CREATE INDEX idx_posts_status ON posts(status);
CREATE INDEX idx_posts_type ON posts(post_type);
CREATE INDEX idx_posts_expires_at ON posts(expires_at);

-- =====================================================
-- MATCHES TABLE
-- Tracks swap matches between two posts
-- =====================================================
CREATE TYPE match_status AS ENUM ('pending', 'accepted', 'declined', 'expired', 'withdrawn');

CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_a_id UUID REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
    post_b_id UUID REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
    user_a_id UUID REFERENCES auth.users(id) NOT NULL,
    user_b_id UUID REFERENCES auth.users(id) NOT NULL,
    status match_status DEFAULT 'pending',
    user_a_accepted BOOLEAN DEFAULT FALSE,
    user_b_accepted BOOLEAN DEFAULT FALSE,
    user_a_accepted_at TIMESTAMPTZ,
    user_b_accepted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL, -- 24-hour window
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_a_id, post_b_id)
);

-- Indexes for match lookups
CREATE INDEX idx_matches_post_a ON matches(post_a_id);
CREATE INDEX idx_matches_post_b ON matches(post_b_id);
CREATE INDEX idx_matches_user_a ON matches(user_a_id);
CREATE INDEX idx_matches_user_b ON matches(user_b_id);
CREATE INDEX idx_matches_status ON matches(status);

-- =====================================================
-- WATCHLIST TABLE
-- Courses users want to monitor for posts
-- =====================================================
CREATE TABLE watchlist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    course_id TEXT REFERENCES courses(course_id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, course_id)
);

-- Index for watchlist lookups
CREATE INDEX idx_watchlist_user_id ON watchlist(user_id);
CREATE INDEX idx_watchlist_course_id ON watchlist(course_id);

-- =====================================================
-- PUSH SUBSCRIPTIONS TABLE
-- Web push notification subscriptions
-- =====================================================
CREATE TABLE push_subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    endpoint TEXT NOT NULL,
    p256dh TEXT NOT NULL,
    auth TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, endpoint)
);

-- =====================================================
-- ROW LEVEL SECURITY POLICIES
-- =====================================================

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE watchlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

-- PROFILES: Users can read all profiles, update only their own
CREATE POLICY "Profiles are viewable by everyone" ON profiles
    FOR SELECT USING (true);

CREATE POLICY "Users can insert their own profile" ON profiles
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own profile" ON profiles
    FOR UPDATE USING (auth.uid() = user_id);

-- COURSES: Everyone can read courses
CREATE POLICY "Courses are viewable by everyone" ON courses
    FOR SELECT USING (true);

-- SECTIONS: Everyone can read sections
CREATE POLICY "Sections are viewable by everyone" ON sections
    FOR SELECT USING (true);

-- POSTS: Everyone can read active posts, users manage their own
CREATE POLICY "Posts are viewable by everyone" ON posts
    FOR SELECT USING (true);

CREATE POLICY "Users can insert own posts" ON posts
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own posts" ON posts
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own posts" ON posts
    FOR DELETE USING (auth.uid() = user_id);

-- MATCHES: Users can only see matches they're part of
CREATE POLICY "Users can view their matches" ON matches
    FOR SELECT USING (auth.uid() = user_a_id OR auth.uid() = user_b_id);

CREATE POLICY "System can create matches" ON matches
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can update their matches" ON matches
    FOR UPDATE USING (auth.uid() = user_a_id OR auth.uid() = user_b_id);

-- WATCHLIST: Users manage only their own watchlist
CREATE POLICY "Users can view their watchlist" ON watchlist
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert to watchlist" ON watchlist
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete from watchlist" ON watchlist
    FOR DELETE USING (auth.uid() = user_id);

-- PUSH SUBSCRIPTIONS: Users manage their own subscriptions
CREATE POLICY "Users can manage own push subscriptions" ON push_subscriptions
    FOR ALL USING (auth.uid() = user_id);

-- =====================================================
-- FUNCTIONS & TRIGGERS
-- =====================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply to relevant tables
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_posts_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_matches_updated_at
    BEFORE UPDATE ON matches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to check profile completion
CREATE OR REPLACE FUNCTION check_profile_complete()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.name IS NOT NULL 
       AND NEW.student_id IS NOT NULL 
       AND NEW.phone IS NOT NULL 
       AND NEW.major IS NOT NULL 
       AND NEW.year IS NOT NULL THEN
        NEW.is_profile_complete = TRUE;
    ELSE
        NEW.is_profile_complete = FALSE;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER check_profile_complete_trigger
    BEFORE INSERT OR UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION check_profile_complete();

-- Function to create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (user_id, username)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'username', NEW.email));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user signup
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to find matching swap posts
CREATE OR REPLACE FUNCTION find_swap_matches(post_id UUID)
RETURNS TABLE (
    matching_post_id UUID,
    matching_user_id UUID
) AS $$
DECLARE
    source_post RECORD;
BEGIN
    -- Get the source post details
    SELECT * INTO source_post FROM posts WHERE id = post_id;
    
    -- Only process swap posts
    IF source_post.post_type != 'swap' THEN
        RETURN;
    END IF;
    
    -- Find reverse matches:
    -- Other post's have_section = source's want_section
    -- Other post's want_section = source's have_section
    RETURN QUERY
    SELECT p.id, p.user_id
    FROM posts p
    WHERE p.id != post_id
      AND p.user_id != source_post.user_id
      AND p.course_id = source_post.course_id
      AND p.post_type = 'swap'
      AND p.status = 'active'
      AND p.is_locked = FALSE
      AND p.have_section = source_post.want_section
      AND p.want_section = source_post.have_section;
END;
$$ LANGUAGE plpgsql;

-- Function to count user's active posts
CREATE OR REPLACE FUNCTION count_active_posts(p_user_id UUID)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::INTEGER
        FROM posts
        WHERE user_id = p_user_id
          AND status IN ('active', 'pending')
    );
END;
$$ LANGUAGE plpgsql;
