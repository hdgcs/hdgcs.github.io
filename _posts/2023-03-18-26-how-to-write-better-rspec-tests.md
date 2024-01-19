---
title:     '如何写好 RSpec 测试'
tags:      [RSpec, Test, Guide]
---

好的测试能保证代码功能正常，还能反向优化功能代码的模块结构，写好测试在软件开发领域会越来越重要。
[RSpec](https://rspec.info/) 是一个测试框架，以可读性好表达能力强著称，本文总结了一些写好 RSpec 测试的经验，
如果你有写 RSpec 测试经验但是不确定怎么写更好，或许本文可以给你一些帮助。

## 例子概览
    
我们来先来看一个实际例子，例子中有两个文件，一个是功能代码，另一个是它对应的测试。

```ruby
# 功能代码
class UsersController
  before_action :authenticate!
  before_action :authorize!
  
  def index
    users = User.by_search(params[:search]).page(params[:page]).per(params[:per])
    
    render status: 200, json: users.as_json
  end
  
  private
  
  def authenticate!
    head 401 unless signed_in?
  end
  
  def authorize!
    head 403 unless current_user.admin?
  end
end
```

在上面的功能代码中，完成了一个基础的用户列表接口，其中接口会先判断是否认证，然后会判断认证用户是否为管理员，最后会根据请求的三个参数
"用户搜索内容", "列表页码", "列表每页数量" 来对用户进行检索，并最终返回检索出来所有符合的用户列表。这里我们假设这些功能都已正确实现。

```ruby
# 测试代码
RSpec.describe UsersController, type: :request do
  let!(:user) { create(:user) }
  let!(:admin) { create(:user, admin: true) }
  
  describe "GET index" do
    subject { get users_path, params: params }
    
    let(:params) { nil }
    let(:signed_user) { admin }
    let(:search_result_count) { 2 }
    
    before do
      create_list(:user, 100)
      allow(User).to receive(:by_search).and_return { |search| search.present? ? User.limit(search_result_count) : User.all }
      sign_in(signed_user) if signed_user # 假设测试框架中已经实现登录方法
    end

    context "with request params" do
      using RSpec::Parameterized::TableSyntax

      where(:search, :page, :per, :expected_data_size) do
        nil           | nil         | nil         | 25 # 假设默认每页数量是 25
        nil           | 1           | 10          | 10
        "search-text" | 1           | 10          | ref(:search_result_count)
      end

      with_them do
        let(:params) { { search: search, page: page, per: per } }

        it "response 200", :aggregate_failures do
          subject

          expect(response).to have_http_status(200)
          expect(json.size).to eq(expected_data_size)
        end
      end
    end
    
    context "when not signed in" do
      let(:signed_user) { nil }
      
      it "response 401" do
        subject
        
        expect(response).to have_http_status(401)
      end
    end
    
    context "when not permitted" do
      let(:signed_user) { user }
      
      it "response 403" do
        subject
        
        expect(response).to have_http_status(403)
      end
    end
  end
end
```

以上是功能的测试代码，它总共运行了 6 个测试用例（通过 [rspec-parameterized](https://github.com/tomykaira/rspec-parameterized) 动态定义了 4 个）。

在测试文件里，在确保测试能完整覆盖全部功能的前提下，我们希望尽量写好它，接下来我会讲解写好的测试需要关注哪些点。

## 关注点一：测试分层要尽量少

对于测试，首先我们要关注的是用例嵌套层数，我的建议是越少越好，因为 RSpec 的测试变量/条件会定义在各个层中，如果嵌套层数多了，很难直观的确定一个
藏在最深处的测试的所有条件。

以下是我们例子中的测试分层图：
![测试分层图](/assets/img/26-test-structure.png)

从分层图里可以看到最大层数的测试分层结构是：

```
RSpec.describe UsersController
  describe "GET index"
    context "with request params"
      context "with request params 1"
        it "response 200"
```

前两层是测试规范里面必须的（一个对应文件，一个对应测试功能）。然后第四层就是一个明确的测试场景，主要的条件就是在这里设置的，第五层是一个断言，
这些是保持规范且最精简的用例嵌套层数。 对于特殊的第三层，他实际是为
[rspec-parameterized](https://github.com/tomykaira/rspec-parameterized) 便捷批量定义条件加的一层，一般正常四层就够了，
如最后面的两个断言那样。

总结来说对于测试用例我们要尽可能平铺开来减少嵌套层数，一般情况下四层比较合适，特殊情况比如使用一些批量工具时可以多加一层。

## 关注点二：提前初始化全量条件

第二点需要关注的是功能的初始条件，我的建议是提前放到最开始来做，且设置尽可能全量的条件。这是我们测试例子中设置条件的核心代码：

```ruby
# Test
RSpec.describe UsersController, type: :request do
  let!(:user) { create(:user) }
  let!(:admin) { create(:user, admin: true) }
  
  describe "GET index" do
    subject { get users_path, params: params }
    
    let(:params) { nil }
    let(:signed_user) { admin }
    let(:search_result_count) { 2 }

    before do
      create_list(:user, 100)
      allow(User).to receive(:by_search).and_return { |search| search.present? ? User.limit(search_result_count) : User.all }
      sign_in(signed_user) if signed_user
    end
  end
end
```

可以看到最开始设置了两个变量 `user` 和 `admin`，这两个变量在最顶层主要是方便未来其他测试复用。其他条件我们都是在功能测试最开始设置好了，且设置
的条件可以正常获取到用户列表（全量的条件）。这个好处是能让功能逻辑的分支测试用例改动最少，比如后面的 "未登录" 和 "没有权限" 的场景都只需要改动一处：

```ruby
    context "when not signed in" do
      let(:signed_user) { nil }
    end
    
    context "when not permitted" do
      let(:signed_user) { user }
    end
```

相比较而言，还有一种常见的测试用例写法是如下所示：

```ruby
  context "when not signed in" do
  end

  context "when signed in" do
    before do
      sign_in(user)
    end
    
    context "when user permitted" do
      before do
        sign_in(admin)
      end
      
      context "with request params" do
        before do
          create_list(:user, 100)
          allow(User).to receive(:by_search).and_return { |search| search.present? ? User.limit(search_result_count) : User.all }
        end
        # ...
      end
    end
end
```

我们会很容易发现这种写法会造成嵌套层数较深，出现关注点一里说的问题。除此之外还不易维护，因为嵌套一般会依赖功能逻辑顺序，如果这些条件分支更改了顺序就会造成他们对应的用例需要大改。

## 关注点三：注意 Mock 的使用

最后我们来关注一下测试例子中的 Mock 使用，这个也是测试中经常接触的：

```ruby
  describe "GET index" do
    before do
      allow(User).to receive(:by_search).and_return { |search| search.present? ? User.limit(search_result_count) : User.all }
    end

    context "with request params" do
    end
  end
```

在例子中我们 Mock 了 User 类的 `by_search` 方法，根据参数是否存在 Mock 出了两种查询数据，从而保证我们的搜索和分页功能能配合良好，这里我们也有几点值得注意。

首先要保证 Mock 出来的类型有完全覆盖方法所有返回类型。这里我们假设了 `by_search` 方法返回类型只有 `ActiveRecord::Relation`，假如换种假设 `by_search`
还可能返回 `nil` 对象，这时候的 Mock 就有问题了，他应该被修正为：

```ruby
    # 假设 `by_search` 参数为 `admin` 是会返回 `nil`
    allow(User).to receive(:by_search).and_return do |search|
      if search.blank?
        User.all
      elsif search == "admin"
        nil
      else
        User.limit(search_result_count)
      end
    end
```

可能会有人说我缺少了这种类型也没关系吧，反正 `by_search` 的单元测试里面测试全就行吧？其实不是的，因为在修改假设之后功能代码已经出现 bug 了，
如果我们没修正 Mock，那么这个 bug 将没有测试覆盖也就可能不会被发现：
```
    # 当用户搜索 `admin` 时，这里会产生在 nil 对象上调用 `page` 的异常
    users = User.by_search(params[:search]).page(params[:page]).per(params[:per])
```

对于 Mock 的使用我们还要注意，只有对其他依赖类的复杂方法才考虑 Mock，比如测试例子中我们假设的场景是 `by_search` 方法较复杂需要依赖 ES 组件。而像分页方法 `page`, `per`
由于构造测试条件并不难，这里就没有选择 Mock。这里也可以回顾一下上面那点，Mock 用起来也没那么容易，需要处理好方法连接点，因此请尽量减少使用。
