defmodule Mulberry.Document.FacebookAdCompanyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Mulberry.Document
  alias Mulberry.Document.FacebookAdCompany
  alias Mulberry.Text

  describe "new/1" do
    test "creates a new FacebookAdCompany struct with provided attributes" do
      attrs = %{
        page_id: "123456",
        name: "Test Company",
        category: "Technology",
        likes: 10_000,
        verification: "BLUE_VERIFIED"
      }

      company = FacebookAdCompany.new(attrs)

      assert company.page_id == "123456"
      assert company.name == "Test Company"
      assert company.category == "Technology"
      assert company.likes == 10_000
      assert company.verification == "BLUE_VERIFIED"
      assert company.keywords == []
      assert company.meta == []
    end

    test "creates struct with default values for optional fields" do
      company = FacebookAdCompany.new(%{name: "Test"})

      assert company.name == "Test"
      assert company.page_is_deleted == false
      assert company.ig_verification == false
      assert company.keywords == []
      assert company.meta == []
    end
  end

  describe "Document protocol implementation" do
    test "load/2 returns the company unchanged" do
      company = FacebookAdCompany.new(%{name: "Test Company"})
      assert {:ok, ^company} = Document.load(company, [])
    end

    test "generate_summary/2 creates a summary from company data" do
      company =
        FacebookAdCompany.new(%{
          name: "Nike",
          category: "Sportswear Store",
          verification: "BLUE_VERIFIED",
          likes: 39_558_683,
          ig_username: "nike",
          ig_followers: 302_060_936,
          country: "US"
        })

      expect(Text, :summarize, fn content, _opts ->
        assert content =~ "Company: Nike"
        assert content =~ "Category: Sportswear Store"
        assert content =~ "Verification: BLUE_VERIFIED"
        assert content =~ "Facebook Presence"
        assert content =~ "Location: US"
        {:ok, "Nike is a verified sportswear store with millions of followers."}
      end)

      {:ok, updated_company} = Document.generate_summary(company, [])

      assert updated_company.summary ==
               "Nike is a verified sportswear store with millions of followers."
    end

    test "generate_summary/2 handles errors gracefully" do
      company = FacebookAdCompany.new(%{name: "Test"})

      expect(Text, :summarize, fn _content, _opts ->
        {:error, "API error"}
      end)

      assert {:error, "API error", ^company} = Document.generate_summary(company, [])
    end

    test "generate_keywords/2 extracts keywords from company data" do
      company =
        FacebookAdCompany.new(%{
          name: "Nike",
          category: "Sportswear Store",
          entity_type: "BUSINESS",
          country: "US",
          verification: "BLUE_VERIFIED"
        })

      {:ok, updated_company} = Document.generate_keywords(company, [])

      assert "Sportswear Store" in updated_company.keywords
      assert "BUSINESS" in updated_company.keywords
      assert "US" in updated_company.keywords
      assert "Verified" in updated_company.keywords
    end

    test "generate_title/2 returns the company unchanged" do
      company = FacebookAdCompany.new(%{name: "Test Company"})
      assert {:ok, ^company} = Document.generate_title(company, [])
    end

    test "to_text/2 generates a text representation of the company" do
      company =
        FacebookAdCompany.new(%{
          page_id: "15087023444",
          name: "Nike",
          category: "Sportswear Store",
          verification: "BLUE_VERIFIED",
          entity_type: "PERSON_PROFILE",
          likes: 39_558_683,
          ig_username: "nike",
          ig_followers: 302_060_936,
          ig_verification: true,
          country: "US",
          page_alias: "nike",
          page_is_deleted: false
        })

      {:ok, text} = Document.to_text(company, [])

      assert text =~ "=== Facebook Ad Company ==="
      assert text =~ "Name: Nike"
      assert text =~ "Page ID: 15087023444"
      assert text =~ "Category: Sportswear Store"
      assert text =~ "Entity Type: PERSON_PROFILE"
      assert text =~ "Verification: BLUE_VERIFIED"
      assert text =~ "Facebook Presence:\nLikes: 39,558,683"
      assert text =~ "Instagram Presence:\nUsername: @nike"
      assert text =~ "Followers: 302,060,936"
      assert text =~ "Verified: Yes"
      assert text =~ "Location: US"
      assert text =~ "Page Alias: nike"
    end

    test "to_text/2 handles minimal data gracefully" do
      company = FacebookAdCompany.new(%{name: "Test Company"})
      {:ok, text} = Document.to_text(company, [])

      assert text =~ "=== Facebook Ad Company ==="
      assert text =~ "Name: Test Company"
      refute text =~ "Category:"
      refute text =~ "Facebook Presence:"
      refute text =~ "Instagram Presence:"
    end

    test "to_text/2 shows deleted page status" do
      company =
        FacebookAdCompany.new(%{
          name: "Deleted Company",
          page_is_deleted: true
        })

      {:ok, text} = Document.to_text(company, [])
      assert text =~ "Page Status: Deleted"
    end

    test "to_tokens/2 tokenizes the text representation" do
      company = FacebookAdCompany.new(%{name: "Nike", category: "Sportswear"})

      expect(Text, :tokens, fn text ->
        assert text =~ "Nike"
        assert text =~ "Sportswear"
        {:ok, ["Nike", "Sportswear", "Company"]}
      end)

      {:ok, tokens} = Document.to_tokens(company, [])
      assert tokens == ["Nike", "Sportswear", "Company"]
    end

    test "to_chunks/2 splits the text into chunks" do
      company = FacebookAdCompany.new(%{name: "Nike", category: "Sportswear"})

      expected_chunks = [
        %TextChunker.Chunk{text: "chunk1"},
        %TextChunker.Chunk{text: "chunk2"}
      ]

      expect(Text, :split, fn text ->
        assert text =~ "Nike"
        expected_chunks
      end)

      {:ok, chunks} = Document.to_chunks(company, [])
      assert chunks == expected_chunks
    end
  end

  describe "number formatting" do
    test "formats large numbers with commas" do
      company =
        FacebookAdCompany.new(%{
          name: "Test",
          likes: 1_234_567,
          ig_username: "test",
          ig_followers: 987_654_321
        })

      {:ok, text} = Document.to_text(company, [])
      assert text =~ "Likes: 1,234,567"
      assert text =~ "Followers: 987,654,321"
    end
  end
end
