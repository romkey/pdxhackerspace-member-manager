# frozen_string_literal: true

# Pagy configuration
# See https://ddnexus.github.io/pagy/docs/api/pagy#variables

# Default items per page
Pagy::DEFAULT[:limit] = 20

# Use Bootstrap 5 styling
require 'pagy/extras/bootstrap'

# Overflow handling - return empty page instead of raising
require 'pagy/extras/overflow'
Pagy::DEFAULT[:overflow] = :last_page
