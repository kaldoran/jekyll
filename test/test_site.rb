require 'helper'

class TestSite < Test::Unit::TestCase
  context "configuring sites" do
    should "have an array for plugins by default" do
      site = Site.new(Jekyll::Configuration::DEFAULTS)
      assert_equal [File.join(Dir.pwd, '_plugins')], site.plugins
    end

    should "look for plugins under the site directory by default" do
      site = Site.new(Jekyll::Configuration::DEFAULTS.merge({'source' => File.expand_path(source_dir)}))
      assert_equal [File.join(source_dir, '_plugins')], site.plugins
    end

    should "have an array for plugins if passed as a string" do
      site = Site.new(Jekyll::Configuration::DEFAULTS.merge({'plugins' => '/tmp/plugins'}))
      assert_equal ['/tmp/plugins'], site.plugins
    end

    should "have an array for plugins if passed as an array" do
      site = Site.new(Jekyll::Configuration::DEFAULTS.merge({'plugins' => ['/tmp/plugins', '/tmp/otherplugins']}))
      assert_equal ['/tmp/plugins', '/tmp/otherplugins'], site.plugins
    end

    should "have an empty array for plugins if nothing is passed" do
      site = Site.new(Jekyll::Configuration::DEFAULTS.merge({'plugins' => []}))
      assert_equal [], site.plugins
    end

    should "have an empty array for plugins if nil is passed" do
      site = Site.new(Jekyll::Configuration::DEFAULTS.merge({'plugins' => nil}))
      assert_equal [], site.plugins
    end

    should "expose default baseurl" do
      site = Site.new(Jekyll::Configuration::DEFAULTS)
      assert_equal Jekyll::Configuration::DEFAULTS['baseurl'], site.baseurl
    end

    should "expose baseurl passed in from config" do
      site = Site.new(Jekyll::Configuration::DEFAULTS.merge({'baseurl' => '/blog'}))
      assert_equal '/blog', site.baseurl
    end
  end
  context "creating sites" do
    setup do
      stub(Jekyll).configuration do
        Jekyll::Configuration::DEFAULTS.merge({'source' => source_dir, 'destination' => dest_dir})
      end
      @site = Site.new(Jekyll.configuration)
      @num_invalid_posts = 2
    end

    should "have an empty tag hash by default" do
      assert_equal Hash.new, @site.tags
    end

    should "give site with parsed pages and posts to generators" do
      @site.reset
      @site.read
      class MyGenerator < Generator
        def generate(site)
          site.pages.dup.each do |page|
            raise "#{page} isn't a page" unless page.is_a?(Page)
            raise "#{page} doesn't respond to :name" unless page.respond_to?(:name)
          end
        end
      end
      @site.generate
      assert_not_equal 0, @site.pages.size
    end

    should "reset data before processing" do
      clear_dest
      @site.process
      before_posts = @site.posts.length
      before_layouts = @site.layouts.length
      before_categories = @site.categories.length
      before_tags = @site.tags.length
      before_pages = @site.pages.length
      before_static_files = @site.static_files.length
      before_time = @site.time

      @site.process
      assert_equal before_posts, @site.posts.length
      assert_equal before_layouts, @site.layouts.length
      assert_equal before_categories, @site.categories.length
      assert_equal before_tags, @site.tags.length
      assert_equal before_pages, @site.pages.length
      assert_equal before_static_files, @site.static_files.length
      assert before_time <= @site.time
    end

    should "write only modified static files" do
      clear_dest
      StaticFile.reset_cache

      @site.process
      some_static_file = @site.static_files[0].path
      dest = File.expand_path(@site.static_files[0].destination(@site.dest))
      mtime1 = File.stat(dest).mtime.to_i # first run must generate dest file

      # need to sleep because filesystem timestamps have best resolution in seconds
      sleep 1
      @site.process
      mtime2 = File.stat(dest).mtime.to_i
      assert_equal mtime1, mtime2

      # simulate file modification by user
      FileUtils.touch some_static_file

      sleep 1
      @site.process
      mtime3 = File.stat(dest).mtime.to_i
      assert_not_equal mtime2, mtime3 # must be regenerated!

      sleep 1
      @site.process
      mtime4 = File.stat(dest).mtime.to_i
      assert_equal mtime3, mtime4 # no modifications, so must be the same
    end

    should "write static files if not modified but missing in destination" do
      clear_dest
      StaticFile.reset_cache

      @site.process
      some_static_file = @site.static_files[0].path
      dest = File.expand_path(@site.static_files[0].destination(@site.dest))
      mtime1 = File.stat(dest).mtime.to_i # first run must generate dest file

      # need to sleep because filesystem timestamps have best resolution in seconds
      sleep 1
      @site.process
      mtime2 = File.stat(dest).mtime.to_i
      assert_equal mtime1, mtime2

      # simulate destination file deletion
      File.unlink dest

      sleep 1
      @site.process
      mtime3 = File.stat(dest).mtime.to_i
      assert_not_equal mtime2, mtime3 # must be regenerated and differ!

      sleep 1
      @site.process
      mtime4 = File.stat(dest).mtime.to_i
      assert_equal mtime3, mtime4 # no modifications, so must be the same
    end

    should "setup plugins in priority order" do
      assert_equal @site.converters.sort_by(&:class).map{|c|c.class.priority}, @site.converters.map{|c|c.class.priority}
      assert_equal @site.generators.sort_by(&:class).map{|g|g.class.priority}, @site.generators.map{|g|g.class.priority}
    end

    should "sort pages alphabetically" do
      stub.proxy(Dir).entries { |entries| entries.reverse }
      @site.process
      # files in symlinked directories may appear twice
      sorted_pages = %w(
        .htaccess
        about.html
        bar.html
        coffeescript.coffee
        contacts.html
        deal.with.dots.html
        exploit.md
        foo.md
        index.html
        index.html
        main.scss
        main.scss
        properties.html
        sitemap.xml
        static_files.html
        symlinked-file
      )
      assert_equal sorted_pages, @site.pages.map(&:name)
    end

    should "read posts" do
      @site.read_posts('')
      posts = Dir[source_dir('_posts', '**', '*')]
      posts.delete_if { |post| File.directory?(post) && !Post.valid?(post) }
      assert_equal posts.size - @num_invalid_posts, @site.posts.size
    end

    should "expose jekyll version to site payload" do
      assert_equal Jekyll::VERSION, @site.site_payload['jekyll']['version']
    end

    should "expose list of static files to site payload" do
      assert_equal @site.static_files, @site.site_payload['site']['static_files']
    end

    should "deploy payload" do
      clear_dest
      @site.process

      posts = Dir[source_dir("**", "_posts", "**", "*")]
      posts.delete_if { |post| File.directory?(post) && !Post.valid?(post) }
      categories = %w(2013 bar baz category foo z_category publish_test win).sort

      assert_equal posts.size - @num_invalid_posts, @site.posts.size
      assert_equal categories, @site.categories.keys.sort
      assert_equal 5, @site.categories['foo'].size
    end

    context 'error handling' do
      should "raise if destination is included in source" do
        stub(Jekyll).configuration do
          Jekyll::Configuration::DEFAULTS.merge({'source' => source_dir, 'destination' => source_dir})
        end

        assert_raise Jekyll::FatalException do
          site = Site.new(Jekyll.configuration)
        end
      end

      should "raise if destination is source" do
        stub(Jekyll).configuration do
          Jekyll::Configuration::DEFAULTS.merge({'source' => source_dir, 'destination' => File.join(source_dir, "..")})
        end

        assert_raise Jekyll::FatalException do
          site = Site.new(Jekyll.configuration)
        end
      end
    end

    context 'with orphaned files in destination' do
      setup do
        clear_dest
        @site.process
        # generate some orphaned files:
        # single file
        File.open(dest_dir('obsolete.html'), 'w')
        # single file in sub directory
        FileUtils.mkdir(dest_dir('qux'))
        File.open(dest_dir('qux/obsolete.html'), 'w')
        # empty directory
        FileUtils.mkdir(dest_dir('quux'))
        FileUtils.mkdir(dest_dir('.git'))
        FileUtils.mkdir(dest_dir('.svn'))
        FileUtils.mkdir(dest_dir('.hg'))
        # single file in repository
        File.open(dest_dir('.git/HEAD'), 'w')
        File.open(dest_dir('.svn/HEAD'), 'w')
        File.open(dest_dir('.hg/HEAD'), 'w')
      end

      teardown do
        FileUtils.rm_f(dest_dir('obsolete.html'))
        FileUtils.rm_rf(dest_dir('qux'))
        FileUtils.rm_f(dest_dir('quux'))
        FileUtils.rm_rf(dest_dir('.git'))
        FileUtils.rm_rf(dest_dir('.svn'))
        FileUtils.rm_rf(dest_dir('.hg'))
      end

      should 'remove orphaned files in destination' do
        @site.process
        assert !File.exist?(dest_dir('obsolete.html'))
        assert !File.exist?(dest_dir('qux'))
        assert !File.exist?(dest_dir('quux'))
        assert File.exist?(dest_dir('.git'))
        assert File.exist?(dest_dir('.git/HEAD'))
      end

      should 'remove orphaned files in destination - keep_files .svn' do
        config = Jekyll::Configuration::DEFAULTS.merge({'source' => source_dir, 'destination' => dest_dir, 'keep_files' => ['.svn']})
        @site = Site.new(config)
        @site.process
        assert !File.exist?(dest_dir('.htpasswd'))
        assert !File.exist?(dest_dir('obsolete.html'))
        assert !File.exist?(dest_dir('qux'))
        assert !File.exist?(dest_dir('quux'))
        assert !File.exist?(dest_dir('.git'))
        assert !File.exist?(dest_dir('.git/HEAD'))
        assert File.exist?(dest_dir('.svn'))
        assert File.exist?(dest_dir('.svn/HEAD'))
      end
    end

    context 'using a non-default markdown processor in the configuration' do
      should 'use the non-default markdown processor' do
        class Jekyll::Converters::Markdown::CustomMarkdown
          def initialize(*args)
            @args = args
          end

          def convert(*args)
            ""
          end
        end

        custom_processor = "CustomMarkdown"
        s = Site.new(Jekyll.configuration.merge({ 'markdown' => custom_processor }))
        assert_nothing_raised do
          s.process
        end

        # Do some cleanup, we don't like straggling stuff's.
        Jekyll::Converters::Markdown.send(:remove_const, :CustomMarkdown)
      end

      should 'ignore, if there are any bad characters in the class name' do
        module Jekyll::Converters::Markdown::Custom
          class Markdown
            def initialize(*args)
              @args = args
            end

            def convert(*args)
              ""
            end
          end
        end

        bad_processor = "Custom::Markdown"
        s = Site.new(Jekyll.configuration.merge({ 'markdown' => bad_processor }))
        assert_raise Jekyll::FatalException do
          s.process
        end

        # Do some cleanup, we don't like straggling stuff's.
        Jekyll::Converters::Markdown.send(:remove_const, :Custom)
      end
    end

    context 'with an invalid markdown processor in the configuration' do
      should 'not throw an error at initialization time' do
        bad_processor = 'not a processor name'
        assert_nothing_raised do
          Site.new(Jekyll.configuration.merge({ 'markdown' => bad_processor }))
        end
      end

      should 'throw FatalException at process time' do
        bad_processor = 'not a processor name'
        s = Site.new(Jekyll.configuration.merge({ 'markdown' => bad_processor }))
        assert_raise Jekyll::FatalException do
          s.process
        end
      end
    end

    context 'data directory' do
      should 'auto load yaml files' do
        site = Site.new(Jekyll.configuration)
        site.process

        file_content = SafeYAML.load_file(File.join(source_dir, '_data', 'members.yaml'))

        assert_equal site.data['members'], file_content
        assert_equal site.site_payload['site']['data']['members'], file_content
      end

      should 'auto load yml files' do
        site = Site.new(Jekyll.configuration)
        site.process

        file_content = SafeYAML.load_file(File.join(source_dir, '_data', 'languages.yml'))

        assert_equal site.data['languages'], file_content
        assert_equal site.site_payload['site']['data']['languages'], file_content
      end

      should "load symlink files in unsafe mode" do
        site = Site.new(Jekyll.configuration.merge({'safe' => false}))
        site.process

        file_content = SafeYAML.load_file(File.join(source_dir, '_data', 'products.yml'))

        assert_equal site.data['products'], file_content
        assert_equal site.site_payload['site']['data']['products'], file_content
      end

      should "not load symlink files in safe mode" do
        site = Site.new(Jekyll.configuration.merge({'safe' => true}))
        site.process

        assert_nil site.data['products']
        assert_nil site.site_payload['site']['data']['products']
      end

      should "load symlink directory in unsafe mode" do
        site = Site.new(Jekyll.configuration.merge({'safe' => false, 'data_source' => File.join('symlink-test', '_data')}))
        site.process

        assert_not_nil site.data['products']
        assert_not_nil site.data['languages']
        assert_not_nil site.data['members']
      end

      should "not load symlink directory in safe mode" do
        site = Site.new(Jekyll.configuration.merge({'safe' => true, 'data_source' => File.join('symlink-test', '_data')}))
        site.process

        assert_nil site.data['products']
        assert_nil site.data['languages']
        assert_nil site.data['members']
      end
    end
  end
end
