# frozen_string_literal: true

require 'date'

# Picks the episode in a show's feed that corresponds to one of our interviews.
#
# Feed titles rarely match ours word for word ("David Deutsch: The Fabric of
# Reality" vs "The Fabric of Reality with DAVID DEUTSCH"), so a candidate has to
# clear two independent bars: it must name the subject, and it must agree with us
# on either wording or publication date.
module EpisodeMatcher
  Candidate = Struct.new(:title, :published_on, :audio_url, :type, :length, :duration, keyword_init: true)

  # Every entry in the anthology is a David Deutsch appearance, so a feed episode
  # that never names him is a false positive however well its date lines up.
  SUBJECT_TOKENS = %w[deutsch].freeze

  NAME_TOKENS = %w[david].freeze

  # Shows routinely publish the audio a day or two off the video, and some feeds
  # carry only a date with no time.
  MAX_DATE_DISTANCE_DAYS = 3

  MIN_TITLE_SIMILARITY = 0.5

  STOP_WORDS = %w[a an the with and or of on in to for at by is it his her their from ep episode part].freeze

  class << self
    def best_match(candidates, title:, published_on:)
      scored = candidates.filter_map do |candidate|
        score = score(candidate, title: title, published_on: published_on)
        [candidate, score] if score
      end

      scored.max_by(&:last)&.first
    end

    def score(candidate, title:, published_on:)
      return nil unless candidate.audio_url
      return nil unless names_subject?(candidate.title)

      similarity = title_similarity(candidate.title, title)
      distance = date_distance(candidate.published_on, published_on)

      close_enough = similarity >= MIN_TITLE_SIMILARITY ||
                     (!distance.nil? && distance <= MAX_DATE_DISTANCE_DAYS)
      return nil unless close_enough

      similarity + date_bonus(distance)
    end

    # Scored on what is left after the subject's name, since every title in the
    # anthology carries it: "David Deutsch Interview" and "The Universal Constructor
    # with David Deutsch" otherwise look like a match on the strength of the name alone.
    def title_similarity(one, other)
      left = tokenize(one) - SUBJECT_TOKENS - NAME_TOKENS
      right = tokenize(other) - SUBJECT_TOKENS - NAME_TOKENS
      return 0.0 if left.empty? || right.empty?

      # Dice coefficient: forgiving of the extra show-branding tokens feed titles carry.
      (2.0 * (left & right).size) / (left.size + right.size)
    end

    def tokenize(text)
      text.to_s.downcase.gsub(/[^a-z0-9\s]/, ' ').split - STOP_WORDS
    end

    def names_subject?(title)
      tokens = tokenize(title)
      SUBJECT_TOKENS.all? { |token| tokens.include?(token) }
    end

    def date_distance(one, other)
      return nil unless one && other

      (to_date(one) - to_date(other)).to_i.abs
    end

    private

    def date_bonus(distance)
      return 0.0 if distance.nil?

      [1.0 - (distance.to_f / MAX_DATE_DISTANCE_DAYS), 0.0].max
    end

    def to_date(value)
      value.is_a?(String) ? Date.parse(value) : value.to_date
    end
  end
end
