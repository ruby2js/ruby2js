Rails.application.routes.draw do
  root "workflows#index"

  resources :workflows do
    resources :nodes, only: [:create, :update, :destroy]
    resources :edges, only: [:create, :destroy]
    member do
      patch :update_positions
    end
  end
end
