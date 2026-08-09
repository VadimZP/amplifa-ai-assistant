# lib/tasks/seeds.rake
# Modular seed tasks for running specific seed files independently

namespace :db do
  namespace :seed do
    desc "Seed only AI prompts (safe to run anytime without affecting other data)"
    task prompts: :environment do
      load Rails.root.join('db/seeds/prompts.rb')
    end
  end
end
