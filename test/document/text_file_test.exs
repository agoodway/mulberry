defmodule Mulberry.Document.FileTest do
  use ExUnit.Case
  doctest Mulberry

  alias Mulberry.Document
  alias Flamel

  describe "fetch/2" do
    test "returns the text of a plain text file" do
      expected_text = """
      Tell me, O muse, of that ingenious hero who travelled far and wide after he had sacked the famous town of Troy. Many cities did he visit, and many were the nations with whose manners and customs he was acquainted; moreover he suffered much by sea while trying to save his own life and bring his men safely home; but do what he might he could not save his men, for they perished through their own sheer folly in eating the cattle of the Sun-god Hyperion; so the god prevented them from ever reaching home. Tell me, too, about all these things, O daughter of Jove, from whatsoever source you may know them.

      So now all who escaped death in battle or by shipwreck had got safely home except Ulysses, and he, though he was longing to return to his wife and country, was detained by the goddess Calypso, who had got him into a large cave and wanted to marry him. But as years went by, there came a time when the gods settled that he should go back to Ithaca; even then, however, when he was among his own people, his troubles were not yet over; nevertheless all the gods had now begun to pity him except Neptune, who still persecuted him without ceasing and would not let him get home.

      Now Neptune had gone off to the Ethiopians, who are at the world's end, and lie in two halves, the one looking West and the other East. He had gone there to accept a hecatomb of sheep and oxen, and was enjoying himself at his festival; but the other gods met in the house of Olympian Jove, and the sire of gods and men spoke first. At that moment he was thinking of Aegisthus, who had been killed by Agamemnon's son Orestes; so he said to the other gods:

      "See now, how men lay blame upon us gods for what is after all nothing but their own folly. Look at Aegisthus; he must needs make love to Agamemnon's wife unrighteously and then kill Agamemnon, though he knew it would be the death of him; for I sent Mercury to warn him not to do either of these things, inasmuch as Orestes would be sure to take his revenge when he grew up and wanted to return home. Mercury told him this in all good will but he would not listen, and now he has paid for everything in full."
      """

      file = Document.File.new(%{path: Path.safe_relative("./test/support/fixtures/files/text_file.txt") |> Flamel.unwrap_ok!()})
      |> Document.load()

      assert file.contents == expected_text


    end
  end
end
