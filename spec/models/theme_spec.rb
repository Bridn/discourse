require 'rails_helper'

describe Theme do

  before do
    Theme.clear_cache!
  end

  let :user do
    Fabricate(:user)
  end

  let :customization_params do
    {name: 'my name', user_id: user.id, header: "my awesome header", stylesheet: "my awesome css", mobile_stylesheet: nil, mobile_header: nil}
  end

  let :customization do
    Theme.create!(customization_params)
  end

  let :customization_with_mobile do
    Theme.create!(customization_params.merge(mobile_stylesheet: ".mobile {better: true;}", mobile_header: "fancy mobile stuff"))
  end

  it 'should set default key when creating a new customization' do
    s = Theme.create!(name: 'my name', user_id: user.id)
    expect(s.key).not_to eq(nil)
  end

  it 'can support child themes' do
    child = Theme.create!(name: '2', user_id: user.id, header: 'World',
                               mobile_header: 'hi', footer: 'footer',
                               stylesheet: '.hello{.world {color: blue;}}')

    parent = Theme.create!(name: '1', user_id: user.id, header: 'Hello',
                              mobile_footer: 'mfooter',
                              mobile_stylesheet: '.hello{margin: 1px;}',
                              stylesheet: 'p{width: 1px;}'
                             )


    parent.add_child_theme!(child)

    expect(Theme.custom_header(parent.key)).to eq("Hello\nWorld")
    expect(Theme.custom_header(parent.key, :mobile)).to eq("hi")
    expect(Theme.custom_footer(parent.key, :mobile)).to eq("mfooter")
    expect(Theme.custom_footer(parent.key)).to eq("footer")

    desktop_css = Theme.custom_stylesheet
    expect(desktop_css).to match(Regexp.new("#{Theme::ENABLED_KEY}.css\\?target=desktop"))

    mobile_css = Theme.custom_stylesheet(nil, :mobile)
    expect(mobile_css).to match(Regexp.new("#{Theme::ENABLED_KEY}.css\\?target=mobile"))

    expect(Theme.enabled_stylesheet_contents).to match(/\.hello \.world/)

    # cache expiry
    c1.enabled = false
    c1.save

    expect(Theme.custom_stylesheet).not_to eq(desktop_css)
    expect(Theme.enabled_stylesheet_contents).not_to match(/\.hello \.world/)
  end

  it 'should be able to look up stylesheets by key' do
    c = Theme.create!(name: '2', user_id: user.id,
                              stylesheet: '.hello{.world {color: blue;}}',
                              mobile_stylesheet: '.world{.hello{color: black;}}')

    expect(Theme.custom_stylesheet(c.key, :mobile)).to match(Regexp.new("#{c.key}.css\\?target=mobile"))
    expect(Theme.custom_stylesheet(c.key)).to match(Regexp.new("#{c.key}.css\\?target=desktop"))

  end

  it 'should provide an awesome error on failure' do
    c = Theme.create!(user_id: user.id, name: "test", stylesheet: "$black: #000; #a { color: $black; }\n\n\nboom", header: '')
    expect(c.stylesheet_baked).to match(/Invalid CSS/)
    expect(c.stylesheet_baked).to match(/line 5/)
    expect(c.mobile_stylesheet_baked).not_to be_present
  end

  it 'should provide an awesome error on failure for mobile too' do
    c = Theme.create!(user_id: user.id, name: "test", stylesheet: '', header: '', mobile_stylesheet: "$black: #000; #a { color: $black; }\n\n\nboom", mobile_header: '')
    expect(c.mobile_stylesheet_baked).to match(/line 5/)
    expect(c.mobile_stylesheet_baked).to match(/footer/)
    expect(c.stylesheet_baked).not_to be_present
  end

  it 'should correct bad html in body_tag_baked and head_tag_baked' do
    c = Theme.create!(user_id: -1, name: "test", head_tag: "<b>I am bold", body_tag: "<b>I am bold")
    expect(c.head_tag_baked).to eq("<b>I am bold</b>")
    expect(c.body_tag_baked).to eq("<b>I am bold</b>")
  end

  it 'should precompile fragments in body and head tags' do
    with_template = <<HTML
    <script type='text/x-handlebars' name='template'>
      {{hello}}
    </script>
    <script type='text/x-handlebars' data-template-name='raw_template.raw'>
      {{hello}}
    </script>
HTML
    c = Theme.create!(user_id: -1, name: "test", head_tag: with_template, body_tag: with_template)
    expect(c.head_tag_baked).to match(/HTMLBars/)
    expect(c.body_tag_baked).to match(/HTMLBars/)
    expect(c.body_tag_baked).to match(/raw-handlebars/)
    expect(c.head_tag_baked).to match(/raw-handlebars/)
  end

  it 'should create body_tag_baked on demand if needed' do
    t = Theme.create!(user_id: -1, name: "test", head_tag: "<b>test")
    t.update_columns(head_tag_baked: nil)
    expect(Theme.custom_head_tag(t.key)).to match(/<b>test<\/b>/)
  end

  context "plugin api" do
    def transpile(html)
      c = Theme.create!(user_id: -1, name: "test", head_tag: html, body_tag: html)
      c.head_tag_baked
    end

    it "transpiles ES6 code" do
      html = <<HTML
        <script type='text/discourse-plugin' version='0.1'>
          const x = 1;
        </script>
HTML

      transpiled = transpile(html)
      expect(transpiled).to match(/\<script\>/)
      expect(transpiled).to match(/var x = 1;/)
      expect(transpiled).to match(/_registerPluginCode\('0.1'/)
    end

    it "converts errors to a script type that is not evaluated" do
      html = <<HTML
        <script type='text/discourse-plugin' version='0.1'>
          const x = 1;
          x = 2;
        </script>
HTML

      transpiled = transpile(html)
      expect(transpiled).to match(/text\/discourse-js-error/)
      expect(transpiled).to match(/read-only/)
    end
  end

end
