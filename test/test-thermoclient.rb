gem "minitest"

require 'minitest/autorun'
require '../thermoclient.rb'
require 'fileutils'

VALID_BOOT_JSON = 'valid-thermo-boot.json.orig'

class TestMeme < Minitest::Test
  def setup
    throw :TestFileNotFound unless File.exist?(VALID_BOOT_JSON)
    FileUtils.cp(VALID_BOOT_JSON, Thermo::BOOT_FILE_NAME)
    throw :TestFileNotFound unless File.exist?(Thermo::BOOT_FILE_NAME)
    @config = Thermo::Configuration.new
  end
  
  def teardown
    FileUtils.safe_unlink(Thermo::BOOT_FILE_NAME)
    throw :TestFileNotDeleted unless !File.exist?(Thermo::BOOT_FILE_NAME)
  end

  def test_boot_config_loader
    assert_equal JSON.parse(IO.read(VALID_BOOT_JSON)), @config.boot
  end

  def test_that_it_will_not_blend
    skip "test"
    #refute_match /^no/i, @meme.will_it_blend?
  end

  def test_that_will_be_skipped
    skip "test this later"
  end
end
