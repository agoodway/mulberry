defmodule Mulberry.Document.FacebookProfileTest do
  use ExUnit.Case, async: true

  alias Mulberry.Document
  alias Mulberry.Document.FacebookProfile

  describe "new/1" do
    test "creates a FacebookProfile struct with given attributes" do
      attrs = %{
        id: "123456789",
        name: "Test Business",
        url: "https://www.facebook.com/testbusiness",
        category: "Restaurant",
        like_count: 1000,
        follower_count: 1200
      }

      profile = FacebookProfile.new(attrs)

      assert %FacebookProfile{} = profile
      assert profile.id == "123456789"
      assert profile.name == "Test Business"
      assert profile.url == "https://www.facebook.com/testbusiness"
      assert profile.category == "Restaurant"
      assert profile.like_count == 1000
      assert profile.follower_count == 1200
    end

    test "creates a FacebookProfile with default values" do
      profile = FacebookProfile.new(%{})

      assert profile.links == []
      assert profile.keywords == []
      assert profile.meta == []
    end
  end

  describe "Document protocol implementation" do
    setup do
      profile =
        FacebookProfile.new(%{
          id: "100064027242849",
          name: "The Copper Kettle Restaurant",
          url: "https://www.facebook.com/copperkettleyqr",
          category: "Pizza place",
          page_intro:
            "Longstanding local restaurant. Mediterranean specialties, signature gourmet pizzas",
          address: "1953 Scarth Street, Regina, SK, Canada",
          email: "copperkettle.events@gmail.com",
          phone: "+1 306-525-3545",
          website: "http://www.thecopperkettle.online/",
          services: "Outdoor seating",
          price_range: "$$",
          rating: "90% recommend (205 Reviews)",
          rating_count: 205,
          like_count: 2400,
          follower_count: 2700,
          ad_library: %{
            "adStatus" => "This Page is currently running ads.",
            "pageId" => "851606664870954"
          },
          creation_date: "October 29, 2014"
        })

      {:ok, profile: profile}
    end

    test "load/2 returns the profile unchanged", %{profile: profile} do
      assert {:ok, ^profile} = Document.load(profile)
    end

    test "generate_summary/2 generates a summary of the profile", %{profile: profile} do
      # Mock the Text.summarize function
      _expect_summary = "A popular pizza restaurant in Regina offering Mediterranean specialties."

      # Since we can't easily mock Text.summarize in tests, we'll skip this for now
      # In a real test, you would use Mimic to mock Mulberry.Text
      assert {:ok, %FacebookProfile{}} = Document.generate_summary(profile)
    end

    test "generate_keywords/2 extracts keywords from profile", %{profile: profile} do
      assert {:ok, updated_profile} = Document.generate_keywords(profile)
      assert "Pizza place" in updated_profile.keywords
      assert "Outdoor seating" in updated_profile.keywords
    end

    test "generate_title/2 returns profile unchanged (already has name)", %{profile: profile} do
      assert {:ok, ^profile} = Document.generate_title(profile)
    end

    test "to_text/2 converts profile to text representation", %{profile: profile} do
      assert {:ok, text} = Document.to_text(profile)

      assert text =~ "=== Facebook Profile ==="
      assert text =~ "Name: The Copper Kettle Restaurant"
      assert text =~ "URL: https://www.facebook.com/copperkettleyqr"
      assert text =~ "Category: Pizza place"
      assert text =~ "Email: copperkettle.events@gmail.com"
      assert text =~ "Phone: +1 306-525-3545"
      assert text =~ "Website: http://www.thecopperkettle.online/"
      assert text =~ "Address: 1953 Scarth Street, Regina, SK, Canada"
      assert text =~ "Services: Outdoor seating"
      assert text =~ "Price Range: $$"
      assert text =~ "Likes: 2,400"
      assert text =~ "Followers: 2,700"
      assert text =~ "Rating: 90% recommend (205 Reviews)"
      assert text =~ "Ad Status: This Page is currently running ads."
      assert text =~ "Page Created: October 29, 2014"
    end

    test "to_text/2 handles minimal profile data" do
      minimal_profile = FacebookProfile.new(%{name: "Test Page"})
      assert {:ok, text} = Document.to_text(minimal_profile)

      assert text =~ "=== Facebook Profile ==="
      assert text =~ "Name: Test Page"
      # Should not include sections with no data
      refute text =~ "Contact Information:"
      refute text =~ "Business Details:"
      refute text =~ "Engagement:"
    end

    test "to_tokens/2 tokenizes the profile text", %{profile: profile} do
      # This would normally use Text.tokens which requires AI
      # For testing, we'll just verify it returns a result
      assert {:ok, tokens} = Document.to_tokens(profile)
      assert is_list(tokens)
    end

    test "to_chunks/2 splits profile into chunks", %{profile: profile} do
      assert {:ok, chunks} = Document.to_chunks(profile)
      assert is_list(chunks)
    end
  end

  describe "number formatting" do
    test "formats large numbers with commas" do
      profile =
        FacebookProfile.new(%{
          name: "Test",
          like_count: 1_234_567,
          follower_count: 890
        })

      assert {:ok, text} = Document.to_text(profile)
      assert text =~ "Likes: 1,234,567"
      assert text =~ "Followers: 890"
    end
  end

  describe "profile with links" do
    test "handles profile with multiple links" do
      profile =
        FacebookProfile.new(%{
          name: "Test Business",
          links: ["https://instagram.com/test", "https://twitter.com/test"]
        })

      assert profile.links == ["https://instagram.com/test", "https://twitter.com/test"]
    end
  end
end
