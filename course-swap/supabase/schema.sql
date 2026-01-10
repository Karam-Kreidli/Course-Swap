-- ============================================
-- University Course Swap App
-- Complete Database Schema + Seed Data
-- For a fresh Supabase project
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- ENUM TYPES
-- ============================================
CREATE TYPE post_type AS ENUM ('swap', 'giveaway');
CREATE TYPE post_status AS ENUM ('active', 'pending', 'completed', 'expired');
CREATE TYPE match_status AS ENUM ('pending', 'accepted', 'declined', 'expired', 'completed');
CREATE TYPE notification_type AS ENUM ('match_found', 'match_accepted', 'match_expired', 'match_declined', 'giveaway_posted', 'reminder');

-- ============================================
-- PROFILES TABLE
-- ============================================
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    name TEXT,
    student_id TEXT,
    phone TEXT,
    major TEXT,
    year TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view all profiles" ON profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- ============================================
-- COURSES TABLE
-- ============================================
CREATE TABLE courses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    course_id TEXT NOT NULL UNIQUE,
    college_code TEXT NOT NULL,
    college_name TEXT NOT NULL,
    course_number TEXT NOT NULL,
    course_name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE courses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Courses are viewable by everyone" ON courses FOR SELECT USING (true);

-- ============================================
-- SECTIONS TABLE
-- ============================================
CREATE TABLE sections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    course_id UUID REFERENCES courses(id) ON DELETE CASCADE,
    section_number TEXT NOT NULL,
    professor TEXT,
    time_slot TEXT,
    room TEXT,
    capacity INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE sections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Sections are viewable by everyone" ON sections FOR SELECT USING (true);

-- ============================================
-- POSTS TABLE
-- ============================================
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    type post_type NOT NULL,
    course_code TEXT NOT NULL,
    course_name TEXT,
    have_section TEXT NOT NULL,
    want_section TEXT,
    status post_status DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '48 hours')
);

ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active posts are viewable by everyone" ON posts FOR SELECT USING (true);
CREATE POLICY "Users can create own posts" ON posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own posts" ON posts FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own posts" ON posts FOR DELETE USING (auth.uid() = user_id);

-- ============================================
-- MATCHES TABLE
-- ============================================
CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_a_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    post_b_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_a_id UUID REFERENCES profiles(id),
    user_b_id UUID REFERENCES profiles(id),
    user_a_accepted BOOLEAN DEFAULT FALSE,
    user_b_accepted BOOLEAN DEFAULT FALSE,
    status match_status DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours'),
    completed_at TIMESTAMPTZ
);

ALTER TABLE matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their matches" ON matches FOR SELECT USING (auth.uid() = user_a_id OR auth.uid() = user_b_id);
CREATE POLICY "System can create matches" ON matches FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update their matches" ON matches FOR UPDATE USING (auth.uid() = user_a_id OR auth.uid() = user_b_id);

-- ============================================
-- WATCHLIST TABLE
-- ============================================
CREATE TABLE watchlist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    course_code TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, course_code)
);

ALTER TABLE watchlist ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own watchlist" ON watchlist FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can add to own watchlist" ON watchlist FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can remove from own watchlist" ON watchlist FOR DELETE USING (auth.uid() = user_id);

-- ============================================
-- NOTIFICATIONS TABLE
-- ============================================
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    type notification_type NOT NULL,
    title TEXT NOT NULL,
    message TEXT,
    data JSONB,
    read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own notifications" ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update own notifications" ON notifications FOR UPDATE USING (auth.uid() = user_id);

-- ============================================
-- FUNCTIONS & TRIGGERS
-- ============================================

-- Function to create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_posts_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Function to find matches when a swap post is created
CREATE OR REPLACE FUNCTION check_for_matches()
RETURNS TRIGGER AS $$
DECLARE
    matching_post RECORD;
BEGIN
    IF NEW.type = 'swap' AND NEW.status = 'active' THEN
        SELECT * INTO matching_post
        FROM posts
        WHERE type = 'swap'
          AND status = 'active'
          AND course_code = NEW.course_code
          AND have_section = NEW.want_section
          AND want_section = NEW.have_section
          AND user_id != NEW.user_id
        LIMIT 1;
        
        IF matching_post.id IS NOT NULL THEN
            INSERT INTO matches (post_a_id, post_b_id, user_a_id, user_b_id)
            VALUES (NEW.id, matching_post.id, NEW.user_id, matching_post.user_id);
            
            UPDATE posts SET status = 'pending' WHERE id = NEW.id;
            UPDATE posts SET status = 'pending' WHERE id = matching_post.id;
            
            INSERT INTO notifications (user_id, type, title, message, data)
            VALUES 
                (NEW.user_id, 'match_found', 'Match Found!', 
                 'Someone wants to swap with you for ' || NEW.course_code,
                 jsonb_build_object('match_id', (SELECT id FROM matches WHERE post_a_id = NEW.id LIMIT 1))),
                (matching_post.user_id, 'match_found', 'Match Found!', 
                 'Someone wants to swap with you for ' || NEW.course_code,
                 jsonb_build_object('match_id', (SELECT id FROM matches WHERE post_b_id = matching_post.id LIMIT 1)));
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_swap_post_created
    AFTER INSERT ON posts
    FOR EACH ROW EXECUTE FUNCTION check_for_matches();

-- Function to handle match acceptance
CREATE OR REPLACE FUNCTION handle_match_acceptance()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user_a_accepted = TRUE AND NEW.user_b_accepted = TRUE THEN
        NEW.status = 'accepted';
        NEW.completed_at = NOW();
        
        INSERT INTO notifications (user_id, type, title, message, data)
        VALUES 
            (NEW.user_a_id, 'match_accepted', 'Swap Confirmed!', 
             'Contact info is now unlocked. Complete your swap!',
             jsonb_build_object('match_id', NEW.id)),
            (NEW.user_b_id, 'match_accepted', 'Swap Confirmed!', 
             'Contact info is now unlocked. Complete your swap!',
             jsonb_build_object('match_id', NEW.id));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_match_updated
    BEFORE UPDATE ON matches
    FOR EACH ROW EXECUTE FUNCTION handle_match_acceptance();

-- ============================================
-- SEED DATA: University of Sharjah Courses
-- ============================================
INSERT INTO courses (course_id, college_code, college_name, course_number, course_name) VALUES
-- Sharia & Islamic Studies
('0103103', '0103', 'College of Sharia & Islamic Studies', '103', 'Islamic System'),
('0103104', '0103', 'College of Sharia & Islamic Studies', '104', 'Prof. Ethics in Islamic Sharia'),
('0104100', '0104', 'College of Sharia & Islamic Studies', '100', 'Islamic Culture'),
('0104130', '0104', 'College of Sharia & Islamic Studies', '130', 'Analytical Biog of the Prophet'),

-- Arts, Humanities & Social Sciences
('0201102', '0201', 'College of Arts, Humanities & Social Sciences', '102', 'Arabic Language'),
('0201140', '0201', 'College of Arts, Humanities & Social Sciences', '140', 'Intro. to Arabic Literature'),
('0202112', '0202', 'College of Arts, Humanities & Social Sciences', '112', 'English for Academic Purposes'),
('0202130', '0202', 'College of Arts, Humanities & Social Sciences', '130', 'French Language'),
('0202227', '0202', 'College of Arts, Humanities & Social Sciences', '227', 'Critical Reading and Writing'),
('0203100', '0203', 'College of Arts, Humanities & Social Sciences', '100', 'Islamic Civilization'),
('0203102', '0203', 'College of Arts, Humanities & Social Sciences', '102', 'History of the Arabian Gulf'),
('0203200', '0203', 'College of Arts, Humanities & Social Sciences', '200', 'Hist of Sciences among Muslims'),
('0204102', '0204', 'College of Arts, Humanities & Social Sciences', '102', 'UAE Society'),
('0204103', '0204', 'College of Arts, Humanities & Social Sciences', '103', 'Principles of Sign Language'),
('0206102', '0206', 'College of Arts, Humanities & Social Sciences', '102', 'Fundamentals/Islamic Education'),
('0206103', '0206', 'College of Arts, Humanities & Social Sciences', '103', 'Introduction to Psychology'),

-- Business Administration
('0302150', '0302', 'College of Business Administration', '150', 'Intro.to Bus for Non-Bus.'),
('0302200', '0302', 'College of Business Administration', '200', 'Fundamentals of Innovation & Entrepreneurship'),
('0308131', '0308', 'College of Business Administration', '131', 'Personal Finance'),
('0308150', '0308', 'College of Business Administration', '150', 'Intro to Economics(Non-B)'),

-- Sciences
('0401142', '0401', 'College of Sciences', '142', 'Man and The Environment'),
('0406102', '0406', 'College of Sciences', '102', 'Introduction to Sustainability'),

-- Health Sciences
('0503101', '0503', 'College of Health Sciences', '101', 'Health and Safety'),
('0505100', '0505', 'College of Health Sciences', '100', 'Understanding Disabilities'),
('0505101', '0505', 'College of Health Sciences', '101', 'Fitness and Wellness'),
('0507101', '0507', 'College of Health Sciences', '101', 'Health Awareness and Nutrition'),

-- Law
('0601109', '0601', 'College of Law', '109', 'Legal Culture'),
('0602246', '0602', 'College of Law', '246', 'Human Rights in Islam'),

-- Fine Arts & Design
('0700100', '0700', 'College of Fine Arts & Design', '100', 'Intro to Islamic Art & Design'),

-- Communication
('0800107', '0800', 'College of Communication', '107', 'Media in Modern Societies'),

-- Medicine
('0900107', '0900', 'College of Medicine', '107', 'History of Medical and H.Sc.'),

-- Chemistry
('1420101', '1420', 'Department of Chemistry', '101', 'General Chemistry (1)'),
('1420102', '1420', 'Department of Chemistry', '102', 'General Chemistry (1) Lab'),

-- Physics
('1430101', '1430', 'Department of Physics', '101', 'Astro & Space Sciences'),
('1430110', '1430', 'Department of Physics', '110', 'Physics I for Sciences'),
('1430116', '1430', 'Department of Physics', '116', 'Physics 1 Lab'),

-- Mathematics
('1440131', '1440', 'Department of Mathematics', '131', 'Calculus I'),
('1440132', '1440', 'Department of Mathematics', '132', 'Calculus II'),
('1440211', '1440', 'Department of Mathematics', '211', 'Linear Algebra I'),
('1440281', '1440', 'Department of Mathematics', '281', 'Introduction to Probability & Statistics'),

-- Biology
('1450100', '1450', 'Department of Biology', '100', 'Biology and Society'),

-- Computer Science / IT
('1501100', '1501', 'Department of Computer Science', '100', 'Introduction to IT (English)'),
('1501116', '1501', 'Department of Computer Science', '116', 'Programming I'),
('1501211', '1501', 'Department of Computer Science', '211', 'Programming II'),
('1501215', '1501', 'Department of Computer Science', '215', 'Data Structures'),
('1501246', '1501', 'Department of Computer Science', '246', 'Object Oriented Design with Java'),
('1501250', '1501', 'Department of Computer Science', '250', 'Networking Fundamentals'),
('1501252', '1501', 'Department of Computer Science', '252', 'Computer Organization and Assembly Language'),
('1501263', '1501', 'Department of Computer Science', '263', 'Introduction to Database Management Systems'),
('1501279', '1501', 'Department of Computer Science', '279', 'Discrete Structures'),
('1501319', '1501', 'Department of Computer Science', '319', 'Programming Languages and Paradigms'),
('1501322', '1501', 'Department of Computer Science', '322', 'Professional, Social and Ethical Issues in CS'),
('1501330', '1501', 'Department of Computer Science', '330', 'Introduction to Artificial Intelligence'),
('1501341', '1501', 'Department of Computer Science', '341', 'Web Programming'),
('1501342', '1501', 'Department of Computer Science', '342', '2D/3D Computer Animation'),
('1501343', '1501', 'Department of Computer Science', '343', 'Interactive 3D Design'),
('1501344', '1501', 'Department of Computer Science', '344', '2D Character Design'),
('1501352', '1501', 'Department of Computer Science', '352', 'Operating Systems'),
('1501365', '1501', 'Department of Computer Science', '365', 'Advanced Database System'),
('1501366', '1501', 'Department of Computer Science', '366', 'Software Engineering'),
('1501370', '1501', 'Department of Computer Science', '370', 'Numerical Methods'),
('1501371', '1501', 'Department of Computer Science', '371', 'Design & Analysis of Algorithms'),
('1501372', '1501', 'Department of Computer Science', '372', 'Formal Languages and Automata Theory'),
('1501394', '1501', 'Department of Computer Science', '394', 'Junior Project in CS'),
('1501397', '1501', 'Department of Computer Science', '397', 'CO-OP Summer Training'),
('1501433', '1501', 'Department of Computer Science', '433', 'Introduction to Computer Vision and Image Processing'),
('1501440', '1501', 'Department of Computer Science', '440', 'Introduction to Computer Graphics'),
('1501441', '1501', 'Department of Computer Science', '441', 'Multimedia Technology'),
('1501442', '1501', 'Department of Computer Science', '442', '3D Character Animation & Visual FX'),
('1501443', '1501', 'Department of Computer Science', '443', 'Human Computer Interaction'),
('1501444', '1501', 'Department of Computer Science', '444', 'Game Design and Development'),
('1501445', '1501', 'Department of Computer Science', '445', 'IT Application in E-Commerce'),
('1501452', '1501', 'Department of Computer Science', '452', 'Introduction to IoT Systems'),
('1501454', '1501', 'Department of Computer Science', '454', 'Cloud Computing'),
('1501455', '1501', 'Department of Computer Science', '455', 'Database Security'),
('1501457', '1501', 'Department of Computer Science', '457', 'Data Hiding'),
('1501458', '1501', 'Department of Computer Science', '458', 'Mobile Application & Design'),
('1501459', '1501', 'Department of Computer Science', '459', 'Information Security'),
('1501465', '1501', 'Department of Computer Science', '465', 'Development of Web Applications'),
('1501490', '1501', 'Department of Computer Science', '490', 'Topics in Computer Science I'),
('1501491', '1501', 'Department of Computer Science', '491', 'Topics in Computer Science II'),
('1501492', '1501', 'Department of Computer Science', '492', 'Special Topics in IT'),
('1501494', '1501', 'Department of Computer Science', '494', 'Senior Project in CS'),

-- Computer Engineering
('1502201', '1502', 'Department of Computer Engineering', '201', 'Digital Logic Design'),
('1502202', '1502', 'Department of Computer Engineering', '202', 'Digital Logic Design Lab'),

-- Education
('1602100', '1602', 'College of Education', '100', 'Smart & Effec. Learning Skills');
