-- Create dictionary system for word validation
-- Created: 2025-01-29

-- Create the dictionary table
CREATE TABLE IF NOT EXISTS public.dictionary (
  word VARCHAR(20) PRIMARY KEY,
  word_length INTEGER GENERATED ALWAYS AS (LENGTH(word)) STORED,
  is_common BOOLEAN DEFAULT false,
  usage_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_dictionary_length ON public.dictionary(word_length);
CREATE INDEX IF NOT EXISTS idx_dictionary_common ON public.dictionary(is_common) WHERE is_common = true;

-- Enable RLS on dictionary table
ALTER TABLE public.dictionary ENABLE ROW LEVEL SECURITY;

-- Allow everyone to read the dictionary
CREATE POLICY "Anyone can read dictionary"
  ON public.dictionary FOR SELECT
  TO anon, authenticated
  USING (true);

-- Only authenticated users can add words (for future admin features)
CREATE POLICY "Authenticated users can insert words"
  ON public.dictionary FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Function to validate a word against the dictionary
CREATE OR REPLACE FUNCTION public.validate_word(
  check_word TEXT
) RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.dictionary
    WHERE word = UPPER(check_word)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.validate_word(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.validate_word(TEXT) TO authenticated;

-- Function to batch validate multiple words
CREATE OR REPLACE FUNCTION public.validate_words(
  check_words TEXT[]
) RETURNS TABLE(word TEXT, is_valid BOOLEAN) AS $$
BEGIN
  RETURN QUERY
  SELECT
    w.word,
    EXISTS(SELECT 1 FROM public.dictionary WHERE dictionary.word = UPPER(w.word))
  FROM UNNEST(check_words) AS w(word);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.validate_words(TEXT[]) TO anon;
GRANT EXECUTE ON FUNCTION public.validate_words(TEXT[]) TO authenticated;

-- Function to add usage count when a word is validated (for analytics)
CREATE OR REPLACE FUNCTION public.increment_word_usage(
  used_word TEXT
) RETURNS VOID AS $$
BEGIN
  UPDATE public.dictionary
  SET usage_count = usage_count + 1
  WHERE word = UPPER(used_word);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.increment_word_usage(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.increment_word_usage(TEXT) TO authenticated;

-- Function to get popular words (for hints or suggestions)
CREATE OR REPLACE FUNCTION public.get_popular_words(
  word_len INTEGER DEFAULT NULL,
  limit_count INTEGER DEFAULT 10
) RETURNS TABLE(word TEXT, usage_count INTEGER) AS $$
BEGIN
  RETURN QUERY
  SELECT
    dictionary.word,
    dictionary.usage_count
  FROM public.dictionary
  WHERE (word_len IS NULL OR word_length = word_len)
    AND is_common = true
  ORDER BY dictionary.usage_count DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_popular_words(INTEGER, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_popular_words(INTEGER, INTEGER) TO authenticated;