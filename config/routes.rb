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
        end

        resource :dashboard, only: [ :show ]
      end
    end
  end
end
