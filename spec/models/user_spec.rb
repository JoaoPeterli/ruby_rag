require "rails_helper"

RSpec.describe User do
  def build_user(**overrides)
    build(:user, **overrides)
  end

  it "requires an account, email and password" do
    user = build_user(account: nil, email: nil, password: nil)

    expect(user).not_to be_valid
    expect(user.errors.attribute_names).to include(:account, :email, :password)
  end

  it "normalizes the email to lowercase and stripped" do
    user = build_user(email: "  Fulano@Exemplo.com  ")
    user.save!

    expect(user.email).to eq("fulano@exemplo.com")
  end

  it "rejects a malformed email" do
    user = build_user(email: "nao-e-um-email")

    expect(user).not_to be_valid
    expect(user.errors.attribute_names).to include(:email)
  end

  it "rejects a duplicate email (case-insensitive)" do
    build_user(email: "duplicado@teste.com").save!
    user = build_user(email: "Duplicado@Teste.com")

    expect(user).not_to be_valid
    expect(user.errors.attribute_names).to include(:email)
  end

  it "rejects a password shorter than 8 characters" do
    user = build_user(password: "1234567")

    expect(user).not_to be_valid
    expect(user.errors.attribute_names).to include(:password)
  end

  it "authenticates with the correct password and rejects the wrong one" do
    user = build_user(password: "senha1234")
    user.save!

    expect(user.authenticate("senha1234")).to eq(user)
    expect(user.authenticate("senha-errada")).to be_falsey
  end

  describe ".active" do
    it "returns only active users" do
      active_user = build_user(active: true).tap(&:save!)
      build_user(active: false).save!

      expect(User.active).to contain_exactly(active_user)
    end
  end
end
