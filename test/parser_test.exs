defmodule NostrPublisher.ParserTest do
  use ExUnit.Case, async: true
  
  alias NostrPublisher.Parser

  test "parses Nostr event JSON and extracts attrs and body" do
    json = """
    {
      "id": "test123",
      "pubkey": "testpubkey",
      "created_at": 1675642635,
      "kind": 30023,
      "tags": [
        ["d", "test-article"],
        ["title", "Test Article"],
        ["published_at", "1675642000"],
        ["summary", "A test article"]
      ],
      "content": "# Test Content\\n\\nThis is a test.",
      "sig": "testsig"
    }
    """

    {attrs, body} = Parser.parse("test.json", json)

    assert attrs.id == "test-article"
    assert attrs.title == "Test Article"
    assert attrs.description == "A test article"
    assert attrs.author == "testpubkey"
    assert attrs.created_at == 1675642635
    assert attrs.date == ~D[2023-02-06]
    assert body == "# Test Content\n\nThis is a test."
  end

  test "extracts multiple topic tags" do
    json = """
    {
      "pubkey": "testpubkey",
      "created_at": 1675642635,
      "kind": 30023,
      "tags": [
        ["d", "multi-tags"],
        ["t", "elixir"],
        ["t", "nostr"],
        ["t", "tutorial"]
      ],
      "content": "Test content"
    }
    """

    {attrs, _body} = Parser.parse("test.json", json)

    assert attrs.tags == ["elixir", "nostr", "tutorial"]
  end

  test "handles missing optional tags" do
    json = """
    {
      "pubkey": "testpubkey",
      "created_at": 1675642635,
      "kind": 30023,
      "tags": [
        ["d", "minimal"]
      ],
      "content": "Minimal content"
    }
    """

    {attrs, body} = Parser.parse("test.json", json)

    assert attrs.id == "minimal"
    assert attrs.author == "testpubkey"
    assert body == "Minimal content"
    refute Map.has_key?(attrs, :title)
    refute Map.has_key?(attrs, :tags)
    refute Map.has_key?(attrs, :date)
  end

  test "raises on invalid JSON" do
    assert_raise RuntimeError, ~r/Failed to parse/, fn ->
      Parser.parse("test.json", "not valid json")
    end
  end
end

