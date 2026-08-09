# frozen_string_literal: true

# Rake tasks for testing enrichment services during development.
# These tasks allow manual testing of individual scraping and inference steps.

namespace :enrichment do
  desc 'Scrape a LinkedIn profile by URL or username'
  task :scrape_linkedin, [:identifier] => :environment do |_t, args|
    identifier = args[:identifier]

    if identifier.blank?
      puts 'Usage: rake enrichment:scrape_linkedin[linkedin_url_or_username]'
      puts ''
      puts 'Examples:'
      puts '  rake enrichment:scrape_linkedin[neal-mohan]'
      puts '  rake enrichment:scrape_linkedin[https://linkedin.com/in/neal-mohan]'
      exit 1
    end

    puts '=' * 60
    puts 'LinkedIn Profile Scraper'
    puts '=' * 60
    puts ''

    unless ApifyCredentials.configured?
      puts '❌ Error: Apify credentials not configured'
      puts ''
      puts 'Set APIFY_API_TOKEN environment variable or add to Rails credentials:'
      puts '  apify:'
      puts '    api_token: your_token_here'
      exit 1
    end

    puts "Identifier: #{identifier}"
    puts 'Scraping...'
    puts ''

    start_time = Time.current
    scraper = LinkedinProfileScraper.new(identifier)
    result = scraper.scrape
    elapsed = ((Time.current - start_time) * 1000).round

    if result.success?
      puts "✅ Success! (#{elapsed}ms)"
      puts ''
      puts 'Profile Data:'
      puts '-' * 40

      data = result.data
      puts "Name: #{data[:full_name]}"
      puts "Headline: #{data[:headline]}"
      puts "Location: #{data[:location]}"
      puts "Email: #{data[:email] || '(not available)'}"
      puts ''
      puts 'Summary:'
      puts data[:summary]&.truncate(500) || '(none)'
      puts ''

      if data[:experience].present?
        puts "Experience (#{data[:experience].length} positions):"
        data[:experience].first(3).each do |exp|
          current = exp[:is_current] ? ' (current)' : ''
          puts "  - #{exp[:title]} at #{exp[:company]}#{current}"
          puts "    Description: #{exp[:description].truncate(100)}" if exp[:description].present?
        end
        puts '  ...' if data[:experience].length > 3
      end

      if data[:education].present?
        puts ''
        puts "Education (#{data[:education].length} entries):"
        data[:education].first(2).each do |edu|
          puts "  - #{edu[:degree]} at #{edu[:school]}"
        end
      end

      if data[:skills].present?
        puts ''
        puts "Skills: #{data[:skills].first(10).join(', ')}"
      end

      if data[:posts].present?
        puts ''
        puts "Posts (#{data[:posts].length} posts):"
        data[:posts].first(3).each do |post|
          puts "  - #{post[:text]&.truncate(100) || post.to_s.truncate(100)}"
        end
      end

      puts ''
      puts "LinkedIn URL: #{data[:linkedin_url]}"
      puts "Scraped at: #{data[:scraped_at]}"

      # Debug: Show raw response keys if DEBUG=1 or if basic fields are empty
      if ENV['DEBUG'].present? || (data[:full_name].blank? && data[:headline].blank?)
        puts ''
        puts '=' * 40
        puts 'DEBUG: Raw API Response'
        puts '=' * 40
        begin
          raw_items = JSON.parse(result.raw_response)
          if raw_items.is_a?(Array) && raw_items.first.is_a?(Hash)
            raw_profile = raw_items.first
            puts "Top-level keys: #{raw_profile.keys.sort.join(', ')}"
            puts ''

            # Show basic_info fields specifically since that's where profile data lives
            if raw_profile['basic_info'].is_a?(Hash)
              puts "basic_info keys: #{raw_profile['basic_info'].keys.sort.join(', ')}"
              puts ''
              puts 'basic_info values:'
              raw_profile['basic_info'].each do |key, value|
                value_preview = case value
                                when Hash then "{...#{value.keys.length} keys}"
                                when Array then "[...#{value.length} items]"
                                when nil then 'null'
                                else value.to_s.truncate(100)
                                end
                puts "  #{key}: #{value_preview}"
              end

              # Show first experience entry keys
              if raw_profile['experience'].is_a?(Array) && raw_profile['experience'].first.is_a?(Hash)
                puts ''
                puts "experience[0] keys: #{raw_profile['experience'].first.keys.sort.join(', ')}"
                puts 'experience[0] values:'
                raw_profile['experience'].first.each do |key, value|
                  value_preview = case value
                                  when Hash then "{...#{value.keys.length} keys}"
                                  when Array then "[...#{value.length} items]"
                                  when nil then 'null'
                                  else value.to_s.truncate(80)
                                  end
                  puts "  #{key}: #{value_preview}"
                end
              end
            else
              puts 'Field values (first 100 chars each):'
              raw_profile.each do |key, value|
                value_preview = case value
                                when Hash then "{...#{value.keys.length} keys}"
                                when Array then "[...#{value.length} items]"
                                when nil then 'null'
                                else value.to_s.truncate(100)
                                end
                puts "  #{key}: #{value_preview}"
              end
            end
          else
            puts 'Raw response (first 2000 chars):'
            puts result.raw_response.truncate(2000)
          end
        rescue JSON::ParserError
          puts 'Raw response (first 2000 chars):'
          puts result.raw_response.truncate(2000)
        end
      end
    else
      puts "❌ Failed! (#{elapsed}ms)"
      puts ''
      puts "Error: #{result.error}"

      if result.raw_response.present?
        puts ''
        puts 'Raw API Response:'
        puts '-' * 40
        puts result.raw_response.truncate(1000)
      end

      puts ''
      puts 'Debug info:'
      puts "  API URL: #{ApifyCredentials.linkedin_scraper_url}"
    end
  end

  desc 'Scrape LinkedIn posts by URL or username'
  task :scrape_linkedin_posts, [:identifier] => :environment do |_t, args|
    identifier = args[:identifier]

    if identifier.blank?
      puts 'Usage: rake enrichment:scrape_linkedin_posts[linkedin_url_or_username]'
      puts ''
      puts 'Examples:'
      puts '  rake enrichment:scrape_linkedin_posts[neal-mohan]'
      puts '  rake enrichment:scrape_linkedin_posts[https://linkedin.com/in/neal-mohan]'
      exit 1
    end

    puts '=' * 60
    puts 'LinkedIn Posts Scraper'
    puts '=' * 60
    puts ''

    unless ApifyCredentials.configured?
      puts 'Error: Apify credentials not configured'
      puts ''
      puts 'Set APIFY_API_TOKEN environment variable or add to Rails credentials:'
      puts '  apify:'
      puts '    api_token: your_token_here'
      exit 1
    end

    puts "Identifier: #{identifier}"
    puts 'Scraping posts...'
    puts ''

    start_time = Time.current
    scraper = LinkedinPostsScraper.new(identifier)
    result = scraper.scrape
    elapsed = ((Time.current - start_time) * 1000).round

    if result.success?
      puts "Success! (#{elapsed}ms)"
      puts ''
      puts 'Posts Data:'
      puts '-' * 40

      data = result.data
      posts = data[:posts] || []
      puts "Total posts: #{data[:post_count]}"
      puts "Scraped at: #{data[:scraped_at]}"
      puts ''

      if posts.any?
        puts 'Recent posts:'
        posts.first(5).each_with_index do |post, i|
          puts ''
          puts "Post #{i + 1}:"
          puts "  Text: #{post[:text]&.truncate(200) || '(no text)'}"
          puts "  URL: #{post[:url]}"
          puts "  Type: #{post[:post_type]}"
          puts "  Posted: #{post[:posted_at]}"
          if post[:stats]
            stats = post[:stats]
            puts "  Reactions: #{stats[:total_reactions]} (#{stats[:likes]} likes, #{stats[:comments]} comments)"
          end
        end
        puts ''
        puts '...' if posts.length > 5
      else
        puts 'No posts found'
      end
    else
      puts "Failed! (#{elapsed}ms)"
      puts ''
      puts "Error: #{result.error}"

      if result.raw_response.present?
        puts ''
        puts 'Raw API Response:'
        puts '-' * 40
        puts result.raw_response.truncate(1000)
      end
    end
  end

  desc 'Download LinkedIn profile photo for a person by ID or email'
  task :download_linkedin_photo, [:identifier] => :environment do |_t, args|
    identifier = args[:identifier]

    if identifier.blank?
      puts 'Usage: rake enrichment:download_linkedin_photo[person_id_or_email]'
      puts ''
      puts 'Examples:'
      puts '  rake enrichment:download_linkedin_photo[123]'
      puts '  rake enrichment:download_linkedin_photo[john@example.com]'
      exit 1
    end

    puts '=' * 60
    puts 'LinkedIn Profile Photo Downloader'
    puts '=' * 60
    puts ''

    person = if identifier.match?(/^\d+$/)
               Person.find_by(id: identifier)
             else
               Person.find_by(email: identifier.downcase)
             end

    if person.nil?
      puts "Error: Person not found with identifier: #{identifier}"
      exit 1
    end

    puts "Person: #{person.display_name} (#{person.email})"
    puts "LinkedIn URL: #{person.linkedin_url || '(none)'}"
    puts ''

    profile_pic_url = person.linkedin_scraped_data&.dig('profile_picture_url')
    puts "Profile Picture URL: #{profile_pic_url || '(none)'}"

    if profile_pic_url.blank?
      puts ''
      puts 'Error: No profile picture URL in scraped data.'
      puts "Scrape LinkedIn profile first: rake enrichment:scrape_linkedin[#{person.linkedin_url || 'URL'}]"
      exit 1
    end

    puts ''
    puts 'Downloading profile photo...'

    start_time = Time.current
    downloader = LinkedinProfilePhotoDownloader.new(person)
    result = downloader.download
    elapsed = ((Time.current - start_time) * 1000).round

    if result.success?
      puts "Success! (#{elapsed}ms)"
      puts ''
      puts 'Photo downloaded and stored:'
      puts "  Filename: #{person.linkedin_profile_photo.filename}"
      puts "  Content type: #{person.linkedin_profile_photo.content_type}"
      puts "  Size: #{person.linkedin_profile_photo.byte_size} bytes"
      puts ''
      puts 'Access URL (in Rails console):'
      puts '  Rails.application.routes.url_helpers.url_for(person.linkedin_profile_photo)'
    else
      puts "Failed! (#{elapsed}ms)"
      puts ''
      puts "Error: #{result.error}"
    end
  end

  desc 'Scrape a company website'
  task :scrape_website, [:url] => :environment do |_t, args|
    url = args[:url]

    if url.blank?
      puts 'Usage: rake enrichment:scrape_website[company_website_url]'
      puts ''
      puts 'Examples:'
      puts '  rake enrichment:scrape_website[https://stripe.com]'
      puts '  rake enrichment:scrape_website[example.com]'
      exit 1
    end

    puts '=' * 60
    puts 'Company Website Scraper'
    puts '=' * 60
    puts ''
    puts "URL: #{url}"
    puts 'Scraping (this may take a moment)...'
    puts ''

    start_time = Time.current
    scraper = CompanyWebsiteScraper.new(url)
    result = scraper.scrape
    elapsed = ((Time.current - start_time) * 1000).round

    if result.success?
      puts "✅ Success! (#{elapsed}ms)"
      puts ''
      puts 'Website Data:'
      puts '-' * 40

      data = result.data
      puts "Title: #{data[:title]}"
      puts "Description: #{data[:description]&.truncate(200)}"
      puts "URL: #{data[:url]}"
      puts ''
      puts 'Stats:'
      puts "  Pages scraped: #{data[:total_pages_scraped]}"
      puts "  PDFs scraped: #{data[:total_pdfs_scraped]}"
      puts "  Content length: #{data[:content_length]} chars"
      puts "  Truncated: #{data[:truncated]}"
      puts ''

      if data[:additional_pages].present?
        puts 'Additional pages:'
        data[:additional_pages].first(5).each do |page|
          puts "  - #{page[:url]}"
        end
        puts '  ...' if data[:additional_pages].length > 5
      end

      if data[:pdfs].present?
        puts ''
        puts 'PDFs found:'
        data[:pdfs].first(3).each do |pdf|
          puts "  - #{pdf[:url]} (#{pdf[:page_count]} pages)"
        end
      end

      puts ''
      puts 'Content preview (first 500 chars):'
      puts '-' * 40
      puts data[:content]&.first(500)
      puts '...'
    else
      puts "❌ Failed! (#{elapsed}ms)"
      puts ''
      puts "Error: #{result.error}"
    end
  end

  desc 'Infer DISC profile for a person by ID or email'
  task :infer_disc, [:identifier] => :environment do |_t, args|
    identifier = args[:identifier]

    if identifier.blank?
      puts 'Usage: rake enrichment:infer_disc[person_id_or_email]'
      puts ''
      puts 'Examples:'
      puts '  rake enrichment:infer_disc[123]'
      puts '  rake enrichment:infer_disc[john@example.com]'
      exit 1
    end

    puts '=' * 60
    puts 'DISC Profile Inferrer'
    puts '=' * 60
    puts ''

    # Find person by ID or email
    person = if identifier.match?(/^\d+$/)
               Person.find_by(id: identifier)
             else
               Person.find_by(email: identifier.downcase)
             end

    if person.nil?
      puts "❌ Error: Person not found with identifier: #{identifier}"
      exit 1
    end

    puts "Person: #{person.display_name} (#{person.email})"
    puts "Job Title: #{person.job_title}"
    puts "Company: #{person.company}"
    puts ''

    if person.linkedin_scraped_data.blank? || person.linkedin_scraped_data == {}
      puts '❌ Error: No LinkedIn data available for this person'
      puts ''
      puts 'First scrape their LinkedIn profile:'
      puts "  rake enrichment:scrape_linkedin[#{person.linkedin_url || 'linkedin_url'}]"
      puts ''
      puts 'Then update the person record with the scraped data.'
      exit 1
    end

    puts 'LinkedIn Data Available:'
    puts "  Headline: #{person.linkedin_headline&.truncate(60)}"
    puts "  Summary: #{person.linkedin_summary.present? ? 'Yes' : 'No'}"
    puts "  Experience: #{person.linkedin_scraped_data['experience']&.length || 0} positions"
    puts "  Skills: #{person.linkedin_scraped_data['skills']&.length || 0}"
    puts ''
    puts 'Inferring DISC profile...'
    puts ''

    start_time = Time.current
    inferrer = DiscProfileInferrer.new(person)
    result = inferrer.infer
    elapsed = ((Time.current - start_time) * 1000).round

    if result.success?
      puts "✅ Success! (#{elapsed}ms)"
      puts ''
      puts 'DISC Profile:'
      puts '-' * 40
      puts "Profile: #{result.profile}"
      puts "Confidence: #{(result.confidence * 100).round}%"
      puts ''
      puts 'Reasoning:'
      puts result.reasoning
      puts ''
      puts 'To save this profile to the person:'
      puts "  person.update_disc_profile!('#{result.profile}', source: 'linkedin_inferred', data: { confidence: #{result.confidence}, reasoning: '...' })"
    else
      puts "❌ Failed! (#{elapsed}ms)"
      puts ''
      puts "Error: #{result.error}"
    end
  end

  desc 'Run full enrichment for a person (LinkedIn + DISC)'
  task :enrich_person, [:identifier] => :environment do |_t, args|
    identifier = args[:identifier]

    if identifier.blank?
      puts 'Usage: rake enrichment:enrich_person[person_id_or_email]'
      exit 1
    end

    puts '=' * 60
    puts 'Full Person Enrichment'
    puts '=' * 60
    puts ''

    # Find person
    person = if identifier.match?(/^\d+$/)
               Person.find_by(id: identifier)
             else
               Person.find_by(email: identifier.downcase)
             end

    if person.nil?
      puts "❌ Error: Person not found: #{identifier}"
      exit 1
    end

    puts "Person: #{person.display_name} (#{person.email})"
    puts "LinkedIn URL: #{person.linkedin_url || '(none)'}"
    puts "Company Website: #{person.company_website || '(none)'}"
    puts ''

    # Step 1: LinkedIn scrape
    if person.linkedin_url.present?
      if person.linkedin_scrape_fresh?
        puts "Step 1: LinkedIn scrape - SKIPPED (cache fresh, scraped #{time_ago_in_words(person.linkedin_scraped_at)} ago)"
      else
        puts 'Step 1: LinkedIn scrape - RUNNING...'
        scraper = LinkedinProfileScraper.new(person.linkedin_url)
        result = scraper.scrape

        if result.success?
          person.update_linkedin_scrape!(result.data)
          puts '         ✅ Success - saved to person'
        else
          puts "         ❌ Failed: #{result.error}"
        end
      end
    else
      puts 'Step 1: LinkedIn scrape - SKIPPED (no LinkedIn URL)'
    end

    # Step 2: DISC inference
    person.reload
    if person.linkedin_scraped_data.present? && person.linkedin_scraped_data != {}
      if person.disc_profile.present? && ENV['FORCE'].blank?
        puts "Step 2: DISC inference - SKIPPED (already has profile: #{person.disc_profile})"
        puts '         Set FORCE=1 to re-infer'
      else
        puts 'Step 2: DISC inference - RUNNING...'
        inferrer = DiscProfileInferrer.new(person)
        result = inferrer.infer

        if result.success?
          person.update_disc_profile!(
            result.profile,
            source: 'linkedin_inferred',
            data: { confidence: result.confidence, reasoning: result.reasoning }
          )
          puts "         ✅ Success - #{result.profile} (#{(result.confidence * 100).round}% confidence)"
        else
          puts "         ❌ Failed: #{result.error}"
        end
      end
    else
      puts 'Step 2: DISC inference - SKIPPED (no LinkedIn data)'
    end

    # Step 3: Company website scrape
    if person.company_website.present?
      if person.company_website_scrape_fresh?
        puts 'Step 3: Company website - SKIPPED (cache fresh)'
      else
        puts 'Step 3: Company website - RUNNING...'
        scraper = CompanyWebsiteScraper.new(person.company_website)
        result = scraper.scrape

        if result.success?
          scrape = WebsiteScrape.cache_for(url: person.company_website, scraped_data: result.data)
          person.update!(company_website_scrape: scrape, company_website_scrape_error: nil)
          puts "         ✅ Success - #{result.data[:content_length]} chars scraped"
        else
          puts "         ❌ Failed: #{result.error}"
        end
      end
    else
      puts 'Step 3: Company website - SKIPPED (no company website)'
    end

    puts ''
    puts 'Enrichment complete!'
    puts ''
    puts 'Final state:'
    person.reload
    puts "  DISC Profile: #{person.disc_profile || '(none)'}"
    puts "  LinkedIn scraped: #{person.linkedin_scraped_at ? time_ago_in_words(person.linkedin_scraped_at) + ' ago' : 'never'}"
    puts "  Company website scraped: #{person.company_website_scraped_at ? time_ago_in_words(person.company_website_scraped_at) + ' ago' : 'never'}"
  end

  desc 'Run full enrichment for a lead via LeadEnrichmentResolver'
  task :enrich_lead, [:lead_id] => :environment do |_t, args|
    lead_id = args[:lead_id]

    if lead_id.blank?
      puts 'Usage: rake enrichment:enrich_lead[lead_id]'
      puts ''
      puts 'Options:'
      puts '  FORCE=1    Force re-enrichment even if cache is fresh'
      puts '  VERBOSE=1  Show detailed step output'
      puts ''
      puts 'Examples:'
      puts '  rake enrichment:enrich_lead[123]'
      puts '  rake enrichment:enrich_lead[123] FORCE=1'
      exit 1
    end

    puts '=' * 60
    puts 'Lead Enrichment (via LeadEnrichmentResolver)'
    puts '=' * 60
    puts ''

    lead = Lead.find_by(id: lead_id)
    if lead.nil?
      puts "❌ Error: Lead not found with ID: #{lead_id}"
      exit 1
    end

    puts "Lead: #{lead.display_name} (#{lead.email})"
    puts "Agent: #{lead.agent.name}" if lead.agent
    puts "Organization: #{lead.organization.name}"
    puts "Person: #{lead.person ? "##{lead.person.id}" : '(not linked)'}"
    puts ''

    force = ENV['FORCE'] == '1'
    verbose = ENV['VERBOSE'] == '1'

    puts "Running enrichment chain#{' (FORCE mode)' if force}..."
    puts ''

    start_time = Time.current
    resolver = LeadEnrichmentResolver.new(lead, force: force)
    result = resolver.resolve!
    ((Time.current - start_time) * 1000).round

    puts '=' * 40
    puts "Results (#{result.total_time_ms}ms total)"
    puts '=' * 40
    puts ''

    result.steps.each do |step|
      icon = case step.status
             when :success then '✅'
             when :skipped then '⏭️'
             when :failed, :error then '❌'
             else '⚪'
             end

      puts "#{icon} #{step.name.to_s.titleize.ljust(25)} #{step.status.to_s.ljust(10)} (#{step.time_ms}ms)"

      puts "   Error: #{step.error}" if step.error.present?

      next unless verbose && step.details.present?

      step.details.each do |key, value|
        puts "   #{key}: #{value.to_s.truncate(80)}"
      end
    end

    if result.errors.any?
      puts ''
      puts '⚠️  Errors encountered:'
      result.errors.each { |e| puts "   - #{e}" }
    end

    puts ''
    puts 'Final lead state:'
    lead.reload
    puts "  Person: ##{lead.person.id}" if lead.person
    puts "  DISC Profile: #{lead.disc_profile || '(none)'}"
    puts "  LinkedIn: #{lead.linkedin_scraped_at ? "scraped #{time_ago_in_words(lead.linkedin_scraped_at)} ago" : 'not scraped'}"
    puts "  Company: #{lead.company_website_scraped_at ? "scraped #{time_ago_in_words(lead.company_website_scraped_at)} ago" : 'not scraped'}"

    if lead.person && lead.person.linkedin_headline.present?
      puts ''
      puts "LinkedIn headline: #{lead.person.linkedin_headline.truncate(60)}"
    end
  end

  desc 'Generate description for an organization'
  task :generate_org_description, [:org_id] => :environment do |_t, args|
    org_id = args[:org_id]

    if org_id.blank?
      puts 'Usage: rake enrichment:generate_org_description[org_id]'
      puts ''
      puts 'Examples:'
      puts '  rake enrichment:generate_org_description[123]'
      puts '  rake enrichment:generate_org_description[123] FORCE=1'
      exit 1
    end

    puts '=' * 60
    puts 'Organization Description Generator'
    puts '=' * 60
    puts ''

    org = Organization.find_by(id: org_id)
    if org.nil?
      puts "❌ Error: Organization not found with ID: #{org_id}"
      exit 1
    end

    puts "Organization: #{org.name}"
    puts "Website: #{org.website || '(none)'}"
    puts ''

    if org.website.blank?
      puts '❌ Error: Organization has no website configured'
      puts "   Set it first: org.update!(website: 'https://example.com')"
      exit 1
    end

    force = ENV['FORCE'] == '1'
    if org.description.present? && org.description_fresh? && !force
      puts "⏭️  Description is fresh (generated #{time_ago_in_words(org.description_generated_at)} ago)"
      puts ''
      puts 'Current description:'
      puts '-' * 40
      puts org.description
      puts ''
      puts 'Use FORCE=1 to regenerate'
      exit 0
    end

    puts 'Generating description from website...'
    puts ''

    start_time = Time.current
    generator = OrganizationDescriptionGenerator.new(org)
    result = generator.generate!
    elapsed = ((Time.current - start_time) * 1000).round

    if result.success?
      puts "✅ Success! (#{elapsed}ms)"
      puts ''
      puts 'Generated description:'
      puts '-' * 40
      puts result.description
      puts ''
      puts "Saved to organization ##{org.id}"
    else
      puts "❌ Failed! (#{elapsed}ms)"
      puts ''
      puts "Error: #{result.error}"
    end
  end

  desc 'Clear enrichment cache for a person'
  task :clear_cache, [:identifier] => :environment do |_t, args|
    identifier = args[:identifier]

    if identifier.blank?
      puts 'Usage: rake enrichment:clear_cache[person_id_or_email]'
      puts ''
      puts 'Options:'
      puts '  DISC=1     Also clear DISC profile'
      puts '  ALL=1      Clear everything including scraped data'
      puts ''
      puts 'Examples:'
      puts '  rake enrichment:clear_cache[123]'
      puts '  rake enrichment:clear_cache[john@example.com]'
      puts '  rake enrichment:clear_cache[123] DISC=1'
      exit 1
    end

    puts '=' * 60
    puts 'Clear Enrichment Cache'
    puts '=' * 60
    puts ''

    # Find person
    person = if identifier.match?(/^\d+$/)
               Person.find_by(id: identifier)
             else
               Person.find_by(email: identifier.downcase)
             end

    if person.nil?
      puts "❌ Error: Person not found: #{identifier}"
      exit 1
    end

    puts "Person: #{person.display_name} (#{person.email})"
    puts ''

    clear_disc = ENV['DISC'] == '1'
    clear_all = ENV['ALL'] == '1'

    updates = {
      linkedin_scraped_at: nil,
      linkedin_scrape_error: nil,
      linkedin_posts_scraped_at: nil,
      linkedin_posts_scrape_error: nil,
      company_website_scraped_at: nil,
      company_website_scrape_error: nil
    }

    if clear_disc || clear_all
      updates[:disc_profile] = nil
      updates[:disc_profile_data] = {}
      updates[:disc_profile_assessed_at] = nil
      updates[:disc_profile_source] = nil
    end

    if clear_all
      updates[:linkedin_scraped_data] = {}
      updates[:linkedin_posts_scraped_data] = {}
      updates[:company_website_scraped_data] = {}
    end

    person.update!(updates)

    puts '✅ Cache cleared:'
    puts '   - LinkedIn profile timestamp'
    puts '   - LinkedIn posts timestamp'
    puts '   - Company website timestamp'
    puts '   - DISC profile' if clear_disc || clear_all
    puts '   - All scraped data' if clear_all
    puts ''
    puts '💡 Run enrichment again:'
    puts "   rake enrichment:enrich_person[#{person.id}]"

    # Also sync any linked leads
    lead_count = person.leads.count
    if lead_count > 0
      person.leads.each(&:sync_from_person!)
      puts ''
      puts "📋 Synced #{lead_count} linked lead(s)"
    end
  end

  desc 'List people and their enrichment status (optionally scoped to agent)'
  task :status, [:agent_id] => :environment do |_t, args|
    agent_id = args[:agent_id]

    puts '=' * 60
    puts 'Enrichment Status'
    puts '=' * 60
    puts ''

    # Determine scope
    if agent_id.present?
      agent = Agent.find_by(id: agent_id)
      if agent.nil?
        puts "❌ Error: Agent not found with ID: #{agent_id}"
        exit 1
      end

      puts "Scoped to Agent ##{agent.id}: #{agent.name}"
      puts "Organization: #{agent.organization.name}"
      puts ''

      # Get people via agent's leads
      person_ids = agent.leads.where.not(person_id: nil).pluck(:person_id).uniq
      people = Person.where(id: person_ids)
      leads = agent.leads
    else
      puts 'All people (no agent filter)'
      puts ''
      people = Person.all
      leads = Lead.all
    end

    total = people.count
    with_linkedin = people.with_linkedin.count
    needs_linkedin = people.needs_linkedin_scrape.count
    needs_disc = people.needs_disc_profile.count
    needs_website = people.needs_company_website_scrape.count

    # Lead stats
    total_leads = leads.count
    leads_with_person = leads.with_person.count
    leads_without_person = leads.without_person.count

    puts "People: #{total}"
    puts "  With LinkedIn URL: #{with_linkedin}"
    puts ''
    puts "Leads: #{total_leads}"
    puts "  Linked to Person: #{leads_with_person}"
    puts "  Not linked: #{leads_without_person}"
    puts ''
    puts 'LinkedIn Scrape:'
    puts "  Fresh: #{total - needs_linkedin}"
    puts "  Needs scrape (stale/never): #{needs_linkedin}"
    puts ''
    puts 'DISC Profile:'
    puts "  Has profile: #{total - needs_disc}"
    puts "  Needs inference: #{needs_disc}"
    puts ''
    puts 'Company Website:'
    puts "  Fresh: #{total - needs_website}"
    puts "  Needs scrape: #{needs_website}"
    puts ''

    if ENV['VERBOSE'].present?
      puts '-' * 60
      puts 'People needing enrichment:'
      puts ''

      people.needs_linkedin_scrape.limit(10).each do |person|
        puts "  #{person.id}: #{person.display_name} - needs LinkedIn scrape"
      end

      people.needs_disc_profile.limit(10).each do |person|
        puts "  #{person.id}: #{person.display_name} - needs DISC inference"
      end

      people.needs_company_website_scrape.limit(10).each do |person|
        puts "  #{person.id}: #{person.display_name} - needs company website scrape"
      end

      if leads_without_person > 0
        puts ''
        puts 'Leads without Person link:'
        leads.without_person.limit(10).each do |lead|
          puts "  #{lead.id}: #{lead.display_name} <#{lead.email}>"
        end
      end
    else
      puts 'Run with VERBOSE=1 to see individual people'
    end
  end

  desc 'Backfill preferred locale and locale source for people with LinkedIn data'
  task backfill_locales: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV['DRY_RUN'])
    force_overwrite_inferred = ActiveModel::Type::Boolean.new.cast(ENV['FORCE_OVERWRITE_INFERRED'])

    puts '=' * 60
    puts 'Locale Backfill'
    puts '=' * 60
    puts ''

    if dry_run
      puts 'DRY RUN: no database changes will be made.'
      puts ''
    end

    if force_overwrite_inferred
      puts 'FORCE OVERWRITE INFERRED: will re-run locale detection and overwrite existing inferred locale values.'
      puts ''
    end

    result = PersonLocaleBackfill.new(
      dry_run: dry_run,
      force_overwrite_inferred: force_overwrite_inferred
    ).run

    puts "Total people scanned: #{result.total_scanned}"
    puts "Eligible with LinkedIn data: #{result.eligible}"
    puts "#{dry_run ? 'Would update' : 'Updated'}: #{result.updated}"
    puts "Skipped (already up-to-date): #{result.skipped}"
    puts "Failed: #{result.failed}"

    if result.errors.any?
      puts ''
      puts 'Errors:'
      result.errors.first(20).each do |error|
        puts "  - Person ##{error[:person_id]} (#{error[:email]}): #{error[:error]}"
      end
      puts '  ...' if result.errors.size > 20
    end
  end

  private

  def time_ago_in_words(time)
    seconds = (Time.current - time).to_i
    case seconds
    when 0..59 then "#{seconds} seconds"
    when 60..3599 then "#{seconds / 60} minutes"
    when 3600..86_399 then "#{seconds / 3600} hours"
    else "#{seconds / 86_400} days"
    end
  end

  desc 'Generate buying signals for the first X leads on an agent'
  task :buying_signals_agent, %i[agent_id limit] => :environment do |_t, args|
    agent = Agent.find_by(id: args[:agent_id])
    limit = args[:limit].presence&.to_i || 10

    if agent.nil?
      puts 'Error: agent not found'
      exit 1
    end

    leads = agent.leads.includes(person: :current_company).order(created_at: :asc).limit(limit)
    company_ids = leads.filter_map { |lead| lead.person&.current_company_id }.uniq

    generated = 0
    failed = 0
    skipped = 0

    company_ids.each do |company_id|
      company = Company.find(company_id)
      result = BuyingSignals::SummaryGenerator.new(
        company: company,
        agent: agent,
        lookback_days: agent.buying_signals_lookback_days
      ).call

      if result.success?
        generated += 1
      else
        failed += 1
        puts "Failed for #{company.name}: #{result.error}"
      end
    rescue StandardError => e
      failed += 1
      puts "Failed for company_id=#{company_id}: #{e.message}"
    end

    skipped = limit - leads.size if leads.size < limit

    puts({ processed_leads: leads.size, generated:, failed:, skipped:, companies: company_ids.size }.to_json)
  end

  desc 'Generate a .docx comparison of buying signals for the first X eligible leads on an agent'
  task :buying_signals_compare, %i[agent_id limit output_path deepseek_models] => :environment do |_t, args|
    agent = Agent.find_by(id: args[:agent_id])
    limit = args[:limit].presence&.to_i || 5
    deepseek_model_ids = args[:deepseek_models].to_s.split(',').map(&:strip).reject(&:blank?)
    deepseek_model_ids = %w[deepseek/deepseek-v4-pro deepseek/deepseek-v4-flash] if deepseek_model_ids.empty?

    if agent.nil?
      puts 'Error: agent not found'
      exit 1
    end

    selected_leads = []
    seen_company_ids = {}

    agent.leads.includes(:person).order(created_at: :asc).each do |lead|
      company = lead.current_company
      next if company.nil? || seen_company_ids[company.id]

      seen_company_ids[company.id] = true
      selected_leads << lead
      break if selected_leads.size >= limit
    end

    output_path = args[:output_path].presence || Rails.root.join(
      'tmp',
      "buying_signals_comparison_agent_#{agent.id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.docx"
    ).to_s

    comparison = BuyingSignals::ComparisonReportGenerator.new(
      agent:,
      leads: selected_leads,
      output_path:,
      deepseek_model_ids:
    )
    result = comparison.call

    puts({
      processed_leads: selected_leads.size,
      output_path: result.document_path,
      lead_ids: selected_leads.map(&:id),
      lead_emails: selected_leads.map(&:email),
      models: BuyingSignals::ComparisonReportGenerator.model_runs_for(deepseek_model_ids:).map do |run|
        { label: run.label, model_id: run.model_id }
      end
    }.to_json)
  end
end
