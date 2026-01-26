defmodule NostrPublisher.ParserTest do
  use ExUnit.Case, async: true

  alias NostrPublisher.Parser
  alias Nostr.Event.Article

  setup_all do
    privkey = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    [privkey: privkey]
  end

  test "parses Nostr event JSON and extracts attrs and body", %{privkey: privkey} do
    content = "# Test Content\\n\\nThis is a test."

    opts = [
      title: "Test Article",
      summary: "so much test",
      published_at: DateTime.new!(~D[2026-01-01], ~T[00:00:00])
    ]

    article = Article.create(content, "test-article", opts)
    json = article.event |> Nostr.Event.sign(privkey) |> JSON.encode!()

    assert {attrs, body} = Parser.parse("test.json", json)

    assert attrs.identifier == "test-article"
    assert attrs.title == opts[:title]
    assert attrs.summary == opts[:summary]
    assert attrs.published_at == opts[:published_at]
    assert attrs.content == body
    assert body == content
  end

  test "extracts multiple topic tags", %{privkey: privkey} do
    opts = [
      title: "Test Article",
      summary: "so much test",
      hashtags: ["elixir", "nostr", "tutorial"]
    ]

    article = Article.create("# Test Content\\n\\nThis is a test.", "test-article", opts)
    json = article.event |> Nostr.Event.sign(privkey) |> JSON.encode!()

    assert {attrs, _body} = Parser.parse("test.json", json)
    assert attrs.hashtags == ["elixir", "nostr", "tutorial"]
  end

  test "handles missing optional tags", %{privkey: privkey} do
    article = Article.create("Minimal content", "minimal")
    json = article.event |> Nostr.Event.sign(privkey) |> JSON.encode!()

    assert {attrs, body} = Parser.parse("test.json", json)

    assert attrs.identifier == "minimal"
    assert body == "Minimal content"
    refute Map.get(attrs, :title)
    refute Map.get(attrs, :tags)
    refute Map.get(attrs, :date)
  end

  test "raises on invalid JSON" do
    assert_raise RuntimeError, ~r/Failed to parse/, fn ->
      Parser.parse("test.json", "not valid json")
    end
  end
end
