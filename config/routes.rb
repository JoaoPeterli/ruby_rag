Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  namespace :api do
    namespace :v1 do
      resources :questions, only: [ :create ] do
        post :stream, on: :collection
      end

      resources :answers, only: [] do
        resources :feedbacks, only: [ :create ]
      end

      namespace :admin do
        resources :documents, only: [ :index, :show ]
        resources :queries, only: [ :index, :show ]
        resources :evaluations, only: [ :index, :show, :create ]

        resources :failures, only: [ :index ] do
          post :retry_all, on: :collection
          post :reconcile_stale_processing, on: :collection
        end

        resource :dashboard, only: [ :show ]
      end
    end
  end

  namespace :admin do
    resource :session, only: [ :new, :create, :destroy ]
    resource :dashboard, only: [ :show ]
    resources :documents, only: [ :index, :show ]
    resources :queries, only: [ :index, :show ]
    resources :evaluations, only: [ :index, :show, :create ]

    resources :failures, only: [ :index ] do
      post :retry_all, on: :collection
      post :reconcile_stale_processing, on: :collection
    end

    # api_only omite :new/:edit dos resources por padrão (routes de
    # formulário não fazem sentido numa API) — precisam ser pedidas
    # explicitamente aqui, já que essa é a parte HTML do app.
    resources :accounts, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      member do
        patch :update_operator
      end
    end

    resources :audit_logs, only: [ :index ]

    resources :users, only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
  end

  # Backoffice por conta (User + senha) -- diferente de /admin (que é
  # o backoffice interno da JLP, autenticado por Account/api_key
  # e enxerga todas as contas).
  namespace :portal do
    resource :session, only: [ :new, :create, :destroy ]
    resource :registration, only: [ :new, :create ]
    resource :password, only: [ :edit, :update ]
    resource :dashboard, only: [ :show ]
    resources :documents, only: [ :index, :show, :new, :create ]

    # Gestão de time (convidar/desativar colega de conta) -- só pro
    # usuário "owner" (quem criou a conta no cadastro). Ver
    # Portal::UsersController#require_owner!.
    resources :users, only: [ :index, :create, :update ]
  end

  root to: "portal/dashboards#show"
end
